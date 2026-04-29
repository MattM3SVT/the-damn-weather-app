import Foundation
import CoreLocation
import os

/// Orchestrates the NWS + METAR supplemental fetch and caches the results.
/// Non-throwing public API: any internal error degrades to an empty consensus
/// (both fields nil), which `applyConsensusOverride` treats as "no override".
public actor ObservationCrossCheckService {
    private let nws: NWSClient
    private let metar: METARClient
    private let log = Logger(subsystem: "DamnWeather", category: "CrossCheck")

    // Caches. Three separate TTLs per the plan. Hydrated from the App Group
    // container on init and rewritten on every mutation so the main app and
    // widget extension share a single view — without this, a widget refresh
    // spawns a fresh empty cache and re-hits NWS/METAR for a station the
    // app already resolved seconds earlier.
    private var observationCache: [String: ObservationCacheEntry] = [:]
    private var stationCache: [String: StationCacheEntry] = [:]
    private var noCoverageCache: [String: Date] = [:]

    // NWS rate-limit gate: ~1.1s between NWS requests across all locations.
    private var nwsTokenReadyAt: Date = .distantPast

    public init() {
        self.nws = NWSClient()
        self.metar = METARClient()
        self.observationCache = CrossCheckCacheStore.loadObservations()
        self.stationCache     = CrossCheckCacheStore.loadStations()
        self.noCoverageCache  = CrossCheckCacheStore.loadNoCoverage()
    }

    /// Public entry point. Never throws. Returns empty consensus when the
    /// location is genuinely outside NWS coverage. On transient failures
    /// (network blip, NWS 5xx, METAR timeout, outer budget expiring) returns
    /// the most recent cached consensus if it's still young enough — see
    /// `stickyFallback`. This keeps the sky-cover override stable across
    /// pull-to-refresh under flaky networks instead of flipping the hero
    /// condition every time a supplemental fetch fails.
    public func fetchSkyConsensus(for location: CLLocation) async -> SkyConsensus {
        // Outer budget guard: race the real work against a timeout racer so that
        // pathological network conditions (DNS blackhole, serial HTTP timeouts,
        // the NWS token wait stacking) can't keep a caller waiting indefinitely.
        let raw: SkyConsensus? = await withTaskGroup(of: SkyConsensus?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return await self.fetchSkyConsensusUnbounded(for: location)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.crossCheckOuterTimeout * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            for await result in group {
                return result
            }
            return nil
        }

        // Outer timeout fired — try sticky fallback.
        guard let result = raw else {
            return stickyFallback(for: location, reason: "outerTimeout") ?? .empty
        }
        // Inner returned, but with no useful data — try sticky fallback only
        // when this isn't a known-no-coverage spot. If we recently learned
        // the location is outside NWS coverage, an empty consensus is the
        // honest answer; don't paper over it with old data.
        if !result.hasUsableData {
            let coverageKey = coverageCacheKey(for: location)
            let isKnownNoCoverage = noCoverageCache[coverageKey].map {
                Date().timeIntervalSince($0) < AppConstants.noNWSCoverageCacheTTL
            } ?? false
            if !isKnownNoCoverage,
               let sticky = stickyFallback(for: location, reason: "transient") {
                return sticky
            }
        }
        return result
    }

    /// Returns the most recent cached consensus for this location if it has
    /// usable data and is younger than `crossCheckStickyMaxAge`. Used to keep
    /// the sky-cover override stable across transient supplemental failures.
    private func stickyFallback(for location: CLLocation, reason: String) -> SkyConsensus? {
        let key = observationCacheKey(for: location)
        guard let entry = observationCache[key],
              entry.consensus.hasUsableData else { return nil }
        let age = Date().timeIntervalSince(entry.fetchedAt)
        guard age < AppConstants.crossCheckStickyMaxAge else { return nil }
        log.info("CrossCheck sticky fallback (\(reason, privacy: .public), age=\(Int(age))s) for \(key, privacy: .public)")
        return entry.consensus
    }

    /// Inner implementation — same logic as before, but caller enforces a timeout.
    private func fetchSkyConsensusUnbounded(for location: CLLocation) async -> SkyConsensus {
        let obsKey = observationCacheKey(for: location)
        let coverageKey = coverageCacheKey(for: location)

        // 1. Observation cache (30 min)
        if let entry = observationCache[obsKey],
           Date().timeIntervalSince(entry.fetchedAt) < AppConstants.observationCacheTTL {
            log.debug("cache hit (observation) for \(obsKey, privacy: .public)")
            return entry.consensus
        }

        // 2. Negative coverage cache (24h)
        if let cachedAt = noCoverageCache[coverageKey],
           Date().timeIntervalSince(cachedAt) < AppConstants.noNWSCoverageCacheTTL {
            log.debug("cache hit (no coverage) for \(coverageKey, privacy: .public)")
            return .empty
        }

        // 3. Resolve station ICAO
        let icao: String?
        do {
            icao = try await resolveICAO(for: location, coverageKey: coverageKey)
        } catch NWSError.outsideCoverage {
            setNoCoverage(coverageKey: coverageKey)
            log.info("NWS outside coverage for \(coverageKey, privacy: .public) — cached 24h")
            return .empty
        } catch {
            log.error("station resolution failed: \(String(describing: error), privacy: .public)")
            return .empty
        }

        guard let icao else {
            log.info("no ASOS-class station found near \(coverageKey, privacy: .public)")
            return .empty
        }

        // 4. Fetch NWS obs + METAR in parallel.
        async let nwsCoverTask = fetchNWSCover(stationID: icao)
        async let metarCoverTask = fetchMETARCover(icao: icao)
        let nwsCover = await nwsCoverTask
        let metarCover = await metarCoverTask

        let consensus = SkyConsensus(nws: nwsCover, metar: metarCover)
        setObservation(key: obsKey, consensus: consensus)
        log.debug("consensus for \(icao, privacy: .public): nws=\(String(describing: nwsCover), privacy: .public) metar=\(String(describing: metarCover), privacy: .public)")
        return consensus
    }

    public func clearCache() {
        observationCache.removeAll()
        stationCache.removeAll()
        noCoverageCache.removeAll()
        CrossCheckCacheStore.saveObservations(observationCache)
        CrossCheckCacheStore.saveStations(stationCache)
        CrossCheckCacheStore.saveNoCoverage(noCoverageCache)
    }

    // MARK: - Private helpers

    /// Returns the nearest ASOS-class ICAO, resolving via NWS points+stations if not cached.
    /// Throws `NWSError.outsideCoverage` so caller can populate the negative cache.
    private func resolveICAO(for location: CLLocation, coverageKey: String) async throws -> String? {
        if let entry = stationCache[coverageKey],
           Date().timeIntervalSince(entry.fetchedAt) < AppConstants.stationResolutionCacheTTL {
            return entry.icao
        }

        await waitForNWSToken()
        let stationsURL = try await nws.fetchObservationStationsURL(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )

        await waitForNWSToken()
        let icao = try await nws.fetchNearestICAO(from: stationsURL)

        if let icao {
            setStation(coverageKey: coverageKey, icao: icao)
        }
        return icao
    }

    // MARK: - LRU cache writers
    // Each cache caps at AppConstants.crossCheckCacheMaxEntries. When capped,
    // the oldest-by-fetchedAt entry is evicted. A user roaming many cities over
    // weeks won't accumulate unbounded memory.

    private func setObservation(key: String, consensus: SkyConsensus) {
        observationCache[key] = ObservationCacheEntry(consensus: consensus, fetchedAt: Date())
        if observationCache.count > AppConstants.crossCheckCacheMaxEntries,
           let oldestKey = observationCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            observationCache.removeValue(forKey: oldestKey)
        }
        CrossCheckCacheStore.saveObservations(observationCache)
    }

    private func setStation(coverageKey: String, icao: String) {
        stationCache[coverageKey] = StationCacheEntry(icao: icao, fetchedAt: Date())
        if stationCache.count > AppConstants.crossCheckCacheMaxEntries,
           let oldestKey = stationCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            stationCache.removeValue(forKey: oldestKey)
        }
        CrossCheckCacheStore.saveStations(stationCache)
    }

    private func setNoCoverage(coverageKey: String) {
        noCoverageCache[coverageKey] = Date()
        if noCoverageCache.count > AppConstants.crossCheckCacheMaxEntries,
           let oldestKey = noCoverageCache.min(by: { $0.value < $1.value })?.key {
            noCoverageCache.removeValue(forKey: oldestKey)
        }
        CrossCheckCacheStore.saveNoCoverage(noCoverageCache)
    }

    private func fetchNWSCover(stationID: String) async -> SkyCover? {
        await waitForNWSToken()
        do {
            return try await nws.fetchSkyCover(stationID: stationID)
        } catch {
            log.error("NWS observation fetch failed for \(stationID, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func fetchMETARCover(icao: String) async -> SkyCover? {
        do {
            return try await metar.fetchSkyCover(icao: icao)
        } catch {
            log.error("METAR fetch failed for \(icao, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Sleeps if needed to respect the ~1.1s inter-request gap, then reserves the next slot.
    private func waitForNWSToken() async {
        let wait = nwsTokenReadyAt.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        nwsTokenReadyAt = Date().addingTimeInterval(AppConstants.nwsMinInterRequestInterval)
    }

    // MARK: - Cache keys

    private func observationCacheKey(for location: CLLocation) -> String {
        // ~111m cells — matches WeatherService cache resolution.
        String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
    }

    private func coverageCacheKey(for location: CLLocation) -> String {
        // ~1.1km cells — station-resolution + no-coverage share this coarser key so
        // tiny GPS jitter doesn't re-resolve.
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }
}
