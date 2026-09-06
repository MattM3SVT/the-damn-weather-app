import Foundation
import CoreLocation
import os

/// Orchestrates AirNow fetch + caching + aggregation into `AirQualityData`.
///
/// Non-throwing public API: any internal error (missing key, invalid key,
/// outside coverage, network failure) returns nil, which callers render as
/// "hide the card". This matches `ObservationCrossCheckService`'s degrade-to-
/// empty contract so a supplemental data source never cascades a failure
/// into the primary weather flow.
public actor AirQualityService {
    private let client: AirNowClient
    private let log = Logger(subsystem: "DamnWeather", category: "AirQuality")

    // Caches hydrated from the App Group container on init, rewritten on every
    // mutation. Two-tier story: a positive cache of recent observations plus
    // a short negative cache for lat/lons outside AirNow's coverage or whose
    // nearby monitors happen to be offline.
    private var observationCache: [String: AirQualityCacheEntry] = [:]
    private var noCoverageCache: [String: Date] = [:]

    // Reporting area name -> USPS state code, needed by the daily historical
    // service. Learned from one extra request the first time we see an area
    // and kept indefinitely, since an area's state doesn't change.
    private var areaStateCache: [String: String] = [:]

    // Request-spacing gate. Prefetching 7 saved locations × 2 requests
    // (current + historical) would fire 14 AirNow requests at once without
    // throttling. The gate serializes requests through the actor so each
    // one starts `airNowMinInterRequestInterval` seconds after the previous.
    private var nextRequestReadyAt: Date = .distantPast

    // One-time flag so we don't spam error logs for every fetch when the key
    // is invalid. Reset on clearCache() to give a fresh retry after config.
    private var hasLoggedUnauthorized = false

    public init() {
        self.client = AirNowClient()
        self.observationCache = AirQualityCacheStore.loadObservations()
        self.noCoverageCache  = AirQualityCacheStore.loadNoCoverage()
        self.areaStateCache   = AirQualityCacheStore.loadAreaStates()
    }

    /// Public entry point. Never throws. Returns nil on permanent failures
    /// (missing/invalid key, outside coverage). On transient failures
    /// (network blip, 5xx, outer timeout) returns the most recent cached
    /// value if it's still young enough to be plausible — see
    /// `stickyFallback`.
    public func fetchAirQuality(for location: CLLocation) async -> AirQualityData? {
        let raced: AirQualityData?? = await withTaskGroup(of: AirQualityData??.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil as AirQualityData?? }
                return await self.fetchUnbounded(for: location)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.airNowOuterTimeout * 1_000_000_000))
                return nil as AirQualityData??
            }
            defer { group.cancelAll() }
            for await result in group {
                // First task to complete wins. Double-optional disambiguates
                // timeout (`nil`) from real-result (`.some(...)`).
                return result
            }
            return nil
        }

        if let real = raced {
            return real
        }
        // Outer timeout fired. Treat as transient and try sticky fallback.
        return stickyFallback(obsKey: observationCacheKey(for: location), reason: "outerTimeout")
    }

    public func clearCache() {
        observationCache.removeAll()
        noCoverageCache.removeAll()
        areaStateCache.removeAll()
        hasLoggedUnauthorized = false
        AirQualityCacheStore.saveObservations(observationCache)
        AirQualityCacheStore.saveNoCoverage(noCoverageCache)
        AirQualityCacheStore.saveAreaStates(areaStateCache)
    }

    // MARK: - Private

    private func fetchUnbounded(for location: CLLocation) async -> AirQualityData? {
        guard let apiKey = AirNowSecrets.apiKey, !apiKey.isEmpty else {
            // Feature silently disabled when key is missing. No warning spam —
            // this is the default state for a fresh clone of the repo.
            return nil
        }

        let obsKey = observationCacheKey(for: location)
        let coverageKey = coverageCacheKey(for: location)

        // 1. Positive cache
        if let entry = observationCache[obsKey],
           Date().timeIntervalSince(entry.fetchedAt) < AppConstants.airQualityCacheTTL {
            log.debug("cache hit (AQI) for \(obsKey, privacy: .public)")
            return entry.data
        }

        // 2. Negative coverage cache
        if let cachedAt = noCoverageCache[coverageKey],
           Date().timeIntervalSince(cachedAt) < AppConstants.airQualityNoCoverageTTL {
            log.debug("cache hit (AQI no coverage) for \(coverageKey, privacy: .public)")
            return nil
        }

        // 3. Fetch current, then historical, sequentially (not `async let`) so
        // every request goes through the same inter-request spacing gate. This
        // keeps us well inside AirNow's rate limit even during a 7-location
        // burst. Historical is normally one request; it costs a second, once
        // per reporting area ever, when the area's state isn't cached yet.
        let currentResult = await fetchCurrent(lat: location.coordinate.latitude,
                                               lon: location.coordinate.longitude,
                                               apiKey: apiKey)

        switch currentResult {
        case .unauthorized:
            // Log once per service lifetime so the developer sees a clear
            // signal. Doesn't bug the end user — the card just stays hidden.
            if !hasLoggedUnauthorized {
                log.error("AirNow rejected the API key (401/403). Verify the key at docs.airnowapi.org.")
                hasLoggedUnauthorized = true
            }
            return stickyFallback(obsKey: obsKey, reason: "unauthorized")
        case .outsideCoverage:
            setNoCoverage(coverageKey: coverageKey)
            log.info("AirNow outside coverage for \(coverageKey, privacy: .public), cached \(Int(AppConstants.airQualityNoCoverageTTL / 3600))h")
            // Outside-coverage is a real "no data here" signal, not a transient
            // failure — don't paper over it with a sticky old reading.
            return nil
        case .failure:
            return stickyFallback(obsKey: obsKey, reason: "transient")
        case .success(let currentReadings):
            let historicalReadings = await fetchHistorical(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                apiKey: apiKey,
                current: currentReadings
            )
            guard let aggregated = aggregate(
                current: currentReadings,
                historical: historicalReadings
            ) else {
                return nil
            }
            setObservation(key: obsKey, data: aggregated)
            return aggregated
        }
    }

    /// Returns the most recent cached AQI for this location if it's young
    /// enough to be plausible (within `airQualityStickyMaxAge`). Used when a
    /// fresh fetch fails so a single transient AirNow blip doesn't make the
    /// hero stat disappear after every pull-to-refresh. Distinct from the
    /// 30-min positive cache, which is read first and gates the fetch
    /// entirely; this is reached only after that cache missed AND the live
    /// fetch failed.
    private func stickyFallback(obsKey: String, reason: String) -> AirQualityData? {
        guard let entry = observationCache[obsKey] else { return nil }
        let age = Date().timeIntervalSince(entry.fetchedAt)
        guard age < AppConstants.airQualityStickyMaxAge else { return nil }
        log.info("AirNow sticky fallback (\(reason, privacy: .public), age=\(Int(age))s) for \(obsKey, privacy: .public)")
        return entry.data
    }

    // MARK: - Fetch helpers

    private enum CurrentResult {
        case success([AirNowReading])
        case outsideCoverage
        case unauthorized
        case failure
    }

    private func fetchCurrent(lat: Double, lon: Double, apiKey: String) async -> CurrentResult {
        await waitForRequestSlot()
        do {
            let rows = try await client.fetchCurrentObservation(lat: lat, lon: lon, apiKey: apiKey)
            return .success(rows)
        } catch AirNowError.outsideCoverage {
            return .outsideCoverage
        } catch AirNowError.unauthorized {
            return .unauthorized
        } catch {
            log.error("AirNow current fetch failed: \(String(describing: error), privacy: .public)")
            return .failure
        }
    }

    /// Best-effort fetch of yesterday's daily AQI. Returns an empty array on
    /// any failure so the caller can still construct `AirQualityData` without
    /// the "vs yesterday" comparison.
    ///
    /// Since June 2026 there is no lat/long historical service, so this works
    /// in three steps: resolve which state the current reading's reporting area
    /// belongs to, pull that whole state's daily observations, then filter back
    /// down to our area. `current` is the already-fetched current reading,
    /// which supplies both the area name to match on and the monitor id used
    /// as a fallback when resolving the state.
    private func fetchHistorical(
        lat: Double,
        lon: Double,
        apiKey: String,
        current: [AirNowReading]
    ) async -> [AirNowReading] {
        guard let area = current.first?.reportingArea, !area.isEmpty else {
            log.debug("AirNow historical skipped: current reading has no reporting area")
            return []
        }
        guard let state = await resolveStateCode(
            for: area, lat: lat, lon: lon, apiKey: apiKey, current: current
        ) else {
            log.debug("AirNow historical skipped: could not resolve state for \(area, privacy: .public)")
            return []
        }

        await waitForRequestSlot()
        let rows: [AirNowReading]
        do {
            rows = try await client.fetchHistoricalDailyObservations(
                stateCode: state, date: yesterdayInDeviceLocalTime(), apiKey: apiKey
            )
        } catch {
            log.debug("AirNow historical fetch failed (non-fatal): \(String(describing: error), privacy: .public)")
            return []
        }

        let matched = rows.filter { Self.areaNamesMatch($0.reportingArea, area) }
        if matched.isEmpty && !rows.isEmpty {
            // The daily service uses a finer-grained set of reporting areas
            // than the current/forecast services in some metros — "Central LA
            // CO" and "Sacramento" have no daily counterpart, for instance. No
            // safe way to substitute a neighbouring area, so we drop the
            // comparison rather than show a number for somewhere else.
            log.debug("AirNow historical has no area matching \(area, privacy: .public) in \(state, privacy: .public)")
        }
        return matched
    }

    /// Compares reporting area names across services. Exact match, ignoring
    /// case and surrounding whitespace — deliberately not fuzzy, because the
    /// near-misses are genuinely different areas ("Central LA CO" vs "S Central
    /// LA CO") and matching them would report a neighbouring area's air as
    /// yours.
    private static func areaNamesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return lhs.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    /// The USPS state code owning `area`, needed by the daily historical
    /// service. Tries, in order:
    ///
    /// 1. The persistent cache — an area's state never changes, so this is
    ///    learned once and thereafter costs nothing.
    /// 2. The current-forecast service, which is authoritative because it's
    ///    AirNow's own area-to-state mapping.
    /// 3. The monitor id from the current reading. Only reached when an area
    ///    has no forecast (Anchorage and San Juan report observations but no
    ///    forecast). Not used first: a monitor can sit in a different state
    ///    than the area it feeds, which would send cross-border metros like
    ///    Memphis to the wrong state.
    private func resolveStateCode(
        for area: String,
        lat: Double,
        lon: Double,
        apiKey: String,
        current: [AirNowReading]
    ) async -> String? {
        if let cached = areaStateCache[area] { return cached }

        await waitForRequestSlot()
        do {
            if let resolved = try await client.fetchReportingAreaState(lat: lat, lon: lon, apiKey: apiKey),
               Self.areaNamesMatch(resolved.reportingArea, area) {
                setAreaState(area: area, state: resolved.stateCode)
                return resolved.stateCode
            }
        } catch {
            log.debug("AirNow forecast lookup failed (non-fatal): \(String(describing: error), privacy: .public)")
        }

        // Deliberately not cached. The forecast lookup is the authoritative
        // answer and this one can be wrong for a cross-border metro, so
        // persisting it would let a single transient forecast outage pin the
        // wrong state for an area indefinitely. Re-deriving it costs nothing,
        // and the areas that actually need it have no forecast to fall back to.
        return current.compactMap { AirNowClient.stateCode(forSiteID: $0.siteID) }.first
    }

    /// Computes "yesterday" using the device's local calendar. AirNow interprets
    /// the date parameter as the location's local calendar day — we assume the
    /// device's timezone is close enough to the location's (true when the user
    /// is at that location). Using a raw 24-hour subtraction in UTC can land
    /// on the wrong calendar day near local midnight.
    private func yesterdayInDeviceLocalTime() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(byAdding: .day, value: -1, to: Date())
            ?? Date().addingTimeInterval(-86400)
    }

    /// Sleeps if needed to respect the inter-request spacing, then reserves
    /// the next slot. Because this runs on the actor, calls are inherently
    /// serialized — callers compete for slots rather than all firing at once.
    private func waitForRequestSlot() async {
        let wait = nextRequestReadyAt.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        nextRequestReadyAt = Date().addingTimeInterval(AppConstants.airNowMinInterRequestInterval)
    }

    // MARK: - Aggregation

    /// Collapses the multi-row AirNow response into a single `AirQualityData`.
    /// Strategy: the overall AQI is the max across all pollutants (standard EPA
    /// method, the worst pollutant drives the index). The primary pollutant is
    /// whichever one produced that max. Pollutant-level concentrations aren't
    /// in AirNow's free CSV, only AQI per pollutant.
    ///
    /// `historical` is yesterday's daily AQI peak per pollutant. We use the max
    /// across those rows as yesterday's overall AQI, shown under the gauge as
    /// a "vs yesterday" comparison.
    private func aggregate(
        current: [AirNowReading],
        historical: [AirNowReading]
    ) -> AirQualityData? {
        // Map current readings to per-pollutant max AQI, deduping (AirNow
        // occasionally returns multiple rows for the same pollutant if several
        // monitors are in range).
        var pollutantMap: [Pollutant: Int] = [:]
        for row in current {
            guard let pollutant = Pollutant(airNowName: row.parameterName) else { continue }
            if let existing = pollutantMap[pollutant] {
                pollutantMap[pollutant] = max(existing, row.aqi)
            } else {
                pollutantMap[pollutant] = row.aqi
            }
        }
        guard !pollutantMap.isEmpty else { return nil }

        // Rows in Apple's display order (see Pollutant.allCases ordering).
        let pollutantRows = Pollutant.allCases.compactMap { p -> PollutantReading? in
            guard let aqi = pollutantMap[p] else { return nil }
            return PollutantReading(pollutant: p, aqi: aqi)
        }

        // Overall AQI = max pollutant AQI. Primary pollutant = whichever
        // pollutant has that max (ties resolved by `Pollutant.allCases` order).
        let (primaryPollutant, overallAQI) = pollutantMap
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return (Pollutant.allCases.firstIndex(of: lhs.key) ?? .max)
                    < (Pollutant.allCases.firstIndex(of: rhs.key) ?? .max)
            }
            .first
            .map { ($0.key, $0.value) }!

        let category = AirQualityCategory.from(aqi: overallAQI)
        let reportingArea = current.first?.reportingArea
        let observedAt = readingTimestamp(from: current) ?? Date()
        let yesterdayAQI = yesterdayDailyMax(from: historical)

        return AirQualityData(
            aqi: overallAQI,
            category: category,
            primaryPollutant: primaryPollutant,
            pollutants: pollutantRows,
            observedAt: observedAt,
            reportingArea: reportingArea,
            yesterdayPeakAQI: yesterdayAQI
        )
    }

    /// Parses the `DateObserved` + `HourObserved` + `LocalTimeZone` fields of
    /// the first row into a real `Date`. We map the abbreviations AirNow emits
    /// explicitly, and fall back to device local for the rest, rather than
    /// relying on iOS's `TimeZone(abbreviation:)` — which resolves "MST" to
    /// Denver and so lands an hour off for Phoenix in summer.
    private func readingTimestamp(from rows: [AirNowReading]) -> Date? {
        guard let first = rows.first else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timezoneForAirNowAbbreviation(first.localTimeZone) ?? .current

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: first.dateObserved) else { return nil }
        return calendar.date(byAdding: .hour, value: first.hourObserved, to: day)
    }

    /// Maps the timezone abbreviations AirNow actually emits (all US/territory
    /// zones) to IANA identifiers. Returns nil for anything outside this set
    /// so the caller falls back to device local.
    ///
    /// The June 2026 services report the *observed* abbreviation rather than
    /// always reporting standard time, which lets us resolve two cases the
    /// legacy feed couldn't (verified live on 2026-09-06):
    ///
    ///   - Denver now reports MDT where Phoenix reports MST; the legacy feed
    ///     said MST for both, so mapping MST to Denver put Phoenix an hour off
    ///     in summer. Each abbreviation now picks a zone whose UTC offset is
    ///     right year-round: MST -> Phoenix (-7 always), MDT -> Denver (-6).
    ///   - Puerto Rico now reports AST (correct, it has no DST) where the
    ///     legacy feed said ADT. Mapping AST to Halifax resolved to -3 in
    ///     summer instead of PR's -4, so AST gets its own zone.
    ///
    /// Alaska reports KST/KDT here and AKT on the legacy feed; neither was
    /// matched before, so Alaskan observations silently fell back to device
    /// local. Both spellings are now mapped.
    static func timezoneForAirNowAbbreviation(_ abbr: String) -> TimeZone? {
        switch abbr {
        case "PST", "PDT":          return TimeZone(identifier: "America/Los_Angeles")
        case "MST":                 return TimeZone(identifier: "America/Phoenix")
        case "MDT":                 return TimeZone(identifier: "America/Denver")
        case "CST", "CDT":          return TimeZone(identifier: "America/Chicago")
        case "EST", "EDT":          return TimeZone(identifier: "America/New_York")
        case "AKST", "AKDT",
             "AKT", "KST", "KDT":   return TimeZone(identifier: "America/Anchorage")
        case "HST", "HAST":         return TimeZone(identifier: "Pacific/Honolulu")
        case "HADT":                return TimeZone(identifier: "America/Adak")
        case "AST":                 return TimeZone(identifier: "America/Puerto_Rico")
        case "ADT":                 return TimeZone(identifier: "America/Halifax")
        case "ChST":                return TimeZone(identifier: "Pacific/Guam")
        case "SST":                 return TimeZone(identifier: "Pacific/Pago_Pago")
        default:                    return nil
        }
    }

    /// Returns yesterday's overall AQI as the max across pollutants in the
    /// historical response. Nil when the historical fetch failed or returned
    /// no rows.
    private func yesterdayDailyMax(from historical: [AirNowReading]) -> Int? {
        guard !historical.isEmpty else { return nil }
        return historical.map(\.aqi).max()
    }

    // MARK: - Cache writers

    private func setObservation(key: String, data: AirQualityData) {
        observationCache[key] = AirQualityCacheEntry(data: data, fetchedAt: Date())
        if observationCache.count > AppConstants.airQualityCacheMaxEntries,
           let oldestKey = observationCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            observationCache.removeValue(forKey: oldestKey)
        }
        AirQualityCacheStore.saveObservations(observationCache)
    }

    private func setAreaState(area: String, state: String) {
        areaStateCache[area] = state
        if areaStateCache.count > AppConstants.airQualityCacheMaxEntries,
           let anyKey = areaStateCache.keys.first {
            // No timestamps here (the mapping never goes stale), so eviction is
            // arbitrary. Reaching 200 distinct reporting areas would take a lot
            // of travelling, and a re-learn is one request.
            areaStateCache.removeValue(forKey: anyKey)
        }
        AirQualityCacheStore.saveAreaStates(areaStateCache)
    }

    private func setNoCoverage(coverageKey: String) {
        noCoverageCache[coverageKey] = Date()
        if noCoverageCache.count > AppConstants.airQualityCacheMaxEntries,
           let oldestKey = noCoverageCache.min(by: { $0.value < $1.value })?.key {
            noCoverageCache.removeValue(forKey: oldestKey)
        }
        AirQualityCacheStore.saveNoCoverage(noCoverageCache)
    }

    // MARK: - Cache keys

    private func observationCacheKey(for location: CLLocation) -> String {
        String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
    }

    private func coverageCacheKey(for location: CLLocation) -> String {
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }
}
