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

    // Caches. Three separate TTLs per the plan.
    private var observationCache: [String: (consensus: SkyConsensus, fetchedAt: Date)] = [:]
    private var stationCache: [String: (icao: String, fetchedAt: Date)] = [:]
    private var noCoverageCache: [String: Date] = [:]

    // NWS rate-limit gate: ~1.1s between NWS requests across all locations.
    private var nwsTokenReadyAt: Date = .distantPast

    public init() {
        self.nws = NWSClient()
        self.metar = METARClient()
    }

    /// Public entry point. Never throws. Returns empty consensus on any failure or
    /// when the location is outside NWS coverage.
    public func fetchSkyConsensus(for location: CLLocation) async -> SkyConsensus {
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
            noCoverageCache[coverageKey] = Date()
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
        observationCache[obsKey] = (consensus, Date())
        log.debug("consensus for \(icao, privacy: .public): nws=\(String(describing: nwsCover), privacy: .public) metar=\(String(describing: metarCover), privacy: .public)")
        return consensus
    }

    public func clearCache() {
        observationCache.removeAll()
        stationCache.removeAll()
        noCoverageCache.removeAll()
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
            stationCache[coverageKey] = (icao, Date())
        }
        return icao
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
