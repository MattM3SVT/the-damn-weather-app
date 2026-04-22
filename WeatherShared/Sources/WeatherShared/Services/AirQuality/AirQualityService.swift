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
    }

    /// Public entry point. Never throws. Returns nil on any failure, outside
    /// coverage, missing/invalid key, or outer-timeout.
    public func fetchAirQuality(for location: CLLocation) async -> AirQualityData? {
        await withTaskGroup(of: AirQualityData??.self) { group in
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
                // First task to complete wins; double-optional disambiguates
                // timeout (`nil`) from success-but-no-data (`.some(nil)`).
                if let unwrapped = result {
                    return unwrapped
                }
                return nil
            }
            return nil
        }
    }

    public func clearCache() {
        observationCache.removeAll()
        noCoverageCache.removeAll()
        hasLoggedUnauthorized = false
        AirQualityCacheStore.saveObservations(observationCache)
        AirQualityCacheStore.saveNoCoverage(noCoverageCache)
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

        // 3. Fetch current + historical sequentially (not `async let`) so both
        // requests go through the same inter-request spacing gate. This keeps
        // us well inside AirNow's rate limit even during a 7-location burst.
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
            return nil
        case .outsideCoverage:
            setNoCoverage(coverageKey: coverageKey)
            log.info("AirNow outside coverage for \(coverageKey, privacy: .public), cached \(Int(AppConstants.airQualityNoCoverageTTL / 3600))h")
            return nil
        case .failure:
            return nil
        case .success(let currentReadings):
            let historicalReadings = await fetchHistorical(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                apiKey: apiKey
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

    /// Best-effort fetch of yesterday's daily AQI (AirNow's free historical
    /// endpoint is daily, not hourly). Returns an empty array on any failure
    /// so the caller can still construct `AirQualityData` without the
    /// "vs yesterday" comparison.
    private func fetchHistorical(lat: Double, lon: Double, apiKey: String) async -> [AirNowReading] {
        let yesterday = yesterdayInDeviceLocalTime()
        await waitForRequestSlot()
        do {
            return try await client.fetchHistoricalObservation(
                lat: lat, lon: lon, date: yesterday, apiKey: apiKey
            )
        } catch {
            log.debug("AirNow historical fetch failed (non-fatal): \(String(describing: error), privacy: .public)")
            return []
        }
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
    /// the first row into a real `Date`. AirNow abbreviations like "MST" are
    /// ambiguous between Phoenix (no DST) and Denver-in-winter; we map the
    /// common US abbreviations explicitly and fall back to device local for
    /// the rest rather than relying on iOS's `TimeZone(abbreviation:)`.
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
    private static func timezoneForAirNowAbbreviation(_ abbr: String) -> TimeZone? {
        switch abbr {
        case "PST", "PDT":        return TimeZone(identifier: "America/Los_Angeles")
        case "MST", "MDT":        return TimeZone(identifier: "America/Denver")
        case "CST", "CDT":        return TimeZone(identifier: "America/Chicago")
        case "EST", "EDT":        return TimeZone(identifier: "America/New_York")
        case "AKST", "AKDT":      return TimeZone(identifier: "America/Anchorage")
        case "HST", "HAST", "HADT": return TimeZone(identifier: "Pacific/Honolulu")
        case "AST", "ADT":        return TimeZone(identifier: "America/Halifax")
        case "ChST":              return TimeZone(identifier: "Pacific/Guam")
        case "SST":               return TimeZone(identifier: "Pacific/Pago_Pago")
        default:                  return nil
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
