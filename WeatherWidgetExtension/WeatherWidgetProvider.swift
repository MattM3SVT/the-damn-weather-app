import WidgetKit
import WeatherKit
import CoreLocation
import MapKit
import WeatherShared
import os.log

private let widgetProviderLog = Logger(subsystem: "DamnWeather", category: "WidgetProvider")

struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let temperature: Int
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let isDay: Bool
    let phrase: String
    let smallPhrase: String   // Shorter phrase for small widget (≤70 chars)
    let feelsLike: Int
    let high: Int
    let low: Int
    let precipProbability: Int
    let hourlyPreview: [HourlyWidgetPoint]
    let dailyPreview: [DailyWidgetPoint]
    let locationName: String
    /// True when the widget is rendering weather for the device's current GPS
    /// location (arrow indicator should show). False when displaying a pinned
    /// saved city the user selected via Edit Widget.
    let isDeviceLocation: Bool

    /// True when no real weather data is available (app hasn't been opened yet).
    var isPlaceholder: Bool { conditionTag == .any && temperature == 0 }

    struct HourlyWidgetPoint: Identifiable {
        let id = UUID()
        let hour: String
        let temp: Int
        let conditionTag: WeatherConditionTag
        let isDay: Bool
    }

    struct DailyWidgetPoint: Identifiable {
        let id = UUID()
        let day: String
        let high: Int
        let low: Int
        let conditionTag: WeatherConditionTag
    }

    static var placeholder: WeatherWidgetEntry {
        return WeatherWidgetEntry(
            date: Date(),
            temperature: 0,
            conditionTag: .any,
            conditionLabel: "",
            isDay: true,
            phrase: "Open The Damn Weather app to get started.",
            smallPhrase: "Open the app to get started.",
            feelsLike: 0,
            high: 0,
            low: 0,
            precipProbability: 0,
            hourlyPreview: [],
            dailyPreview: [],
            locationName: "",
            isDeviceLocation: false
        )
    }
}

struct WeatherWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = WeatherWidgetIntent
    typealias Entry = WeatherWidgetEntry

    private let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )

    /// Held as an instance property so its CLLocationManager delegate survives
    /// past the getTimeline / fetchWeatherEntry async call stack. iOS reloads
    /// this widget's timeline automatically when the device's significant
    /// location changes (enabled via NSWidgetWantsLocation in Info.plist).
    private let locationProvider = WidgetLocationProvider()

    /// Shared across all widget instances so we don't re-hydrate the
    /// on-disk NWS/METAR cache on every refresh. The service is a pure
    /// actor, so it's safe to share across concurrent invocations.
    private static let crossCheck = ObservationCrossCheckService()

    init() {
        // Ensure App Group subdirectories exist — prevents CoreData sandbox errors
        // from WidgetKit's internal bookkeeping on first widget extension launch.
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        ) {
            let appSupport = groupURL.appendingPathComponent("Library/Application Support")
            if !FileManager.default.fileExists(atPath: appSupport.path) {
                try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - AppIntentTimelineProvider

    func placeholder(in context: Context) -> WeatherWidgetEntry {
        // WidgetKit calls this on a very tight budget — any disk I/O risks
        // skipping the first render. Return the hardcoded placeholder only;
        // real data is served from snapshot / timeline once a configuration
        // is present.
        widgetProviderLog.info("placeholder(in:) called")
        return .placeholder
    }

    func snapshot(for configuration: WeatherWidgetIntent, in context: Context) async -> WeatherWidgetEntry {
        widgetProviderLog.info("snapshot called, isPreview=\(context.isPreview) location=\(configuration.location.name, privacy: .public)")
        if let cached = buildCachedEntry(for: configuration.location) {
            return cached
        }
        // No cache hit — widget was just added and app hasn't prefetched yet.
        // Fall back to a live fetch (may take a second but snapshot allows this).
        if let fresh = try? await fetchFreshEntry(for: configuration.location) {
            return fresh
        }
        return .placeholder
    }

    func timeline(for configuration: WeatherWidgetIntent, in context: Context) async -> Timeline<WeatherWidgetEntry> {
        widgetProviderLog.info("timeline called, location=\(configuration.location.name, privacy: .public) id=\(configuration.location.id, privacy: .public)")

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let retryUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()

        // PATH 1 — App Group cache has fresh data for this city. Build a
        // 4-entry rotating-phrase timeline and return.
        //
        // We do NOT kick off a background Task here. WidgetKit suspends the
        // extension shortly after this function returns, so unstructured
        // Tasks can be killed mid-flight. The natural cadence is: cache is
        // considered fresh for `weatherCacheTTL` (15 min); the next timeline
        // call falls through to PATH 2 and performs an awaited fresh fetch.
        if let cached = loadCachedDataForLocation(configuration.location),
           let conditionTag = WeatherConditionTag(rawValue: cached.conditionTag),
           !isMultiCacheStale(cached) {
            widgetProviderLog.info("timeline PATH 1: multi-cache hit for id=\(configuration.location.id, privacy: .public) temp=\(cached.temperature) location=\(cached.locationName, privacy: .public)")

            let entries = buildMultiEntryTimeline(
                from: cached,
                conditionTag: conditionTag,
                entity: configuration.location
            )
            return Timeline(entries: entries, policy: .after(nextUpdate))
        }

        // PATH 2 — No multi-cache; try a live fetch. If that works, cache it
        // and return a single entry. Otherwise short-retry with placeholder.
        widgetProviderLog.warning("timeline PATH 2: multi-cache miss, trying live fetch for \(configuration.location.name, privacy: .public)")
        if let entry = try? await fetchFreshEntry(for: configuration.location) {
            saveFreshDataToMultiCache(entry, for: configuration.location)
            return Timeline(entries: [entry], policy: .after(nextUpdate))
        }

        widgetProviderLog.error("timeline PATH 3: live fetch failed, returning placeholder with short retry")
        return Timeline(entries: [.placeholder], policy: .after(retryUpdate))
    }

    // MARK: - Cached entry helpers

    /// Read a cached entry keyed by the configured location's id. Falls back
    /// to the legacy single-file cache when the multi-cache doesn't have this
    /// entity yet (e.g. first launch after update before `prefetchAllLocations`
    /// has run).
    private func loadCachedDataForLocation(_ entity: LocationEntity) -> CachedWeatherData? {
        if let multi = WidgetDataStore.loadEntry(for: entity.id) {
            return multi
        }
        // Legacy fallback: only for My Location, read the old single-file
        // cache since that's what existing app versions write there.
        if entity.isMyLocation, let single = WidgetDataStore.load() {
            return single
        }
        return nil
    }

    /// Build a widget entry from multi-cache data + live location overrides.
    private func buildCachedEntry(for entity: LocationEntity) -> WeatherWidgetEntry? {
        guard let cached = loadCachedDataForLocation(entity),
              let conditionTag = WeatherConditionTag(rawValue: cached.conditionTag) else {
            return nil
        }
        let forecast = Self.convertForecastPoints(from: cached)
        return WeatherWidgetEntry(
            date: Date(),
            temperature: Int(cached.temperature.rounded()),
            conditionTag: conditionTag,
            conditionLabel: cached.conditionLabel,
            isDay: cached.isDay,
            phrase: cached.phrase,
            smallPhrase: cached.smallPhrase ?? cached.phrase,
            feelsLike: Int(cached.feelsLike.rounded()),
            high: Int(cached.high.rounded()),
            low: Int(cached.low.rounded()),
            precipProbability: 0,
            hourlyPreview: forecast.hourly,
            dailyPreview: forecast.daily,
            locationName: cached.locationName.isEmpty ? entity.name : cached.locationName,
            isDeviceLocation: entity.isMyLocation
        )
    }

    /// Multi-cache entries are considered stale after `weatherCacheTTL`
    /// (15 minutes). Stale entries fall through to PATH 2 and trigger an
    /// awaited fresh fetch; we never return stale data from the timeline
    /// and rely on an unawaited background Task to refresh it.
    private func isMultiCacheStale(_ cached: CachedWeatherData) -> Bool {
        Date().timeIntervalSince(cached.updatedAt) > AppConstants.weatherCacheTTL
    }

    /// 4 entries at ~4-minute intervals rotating through the app's
    /// pre-generated phrases, so the widget shows variety within a single
    /// 15-min refresh window without needing PhraseEngine in the extension.
    private func buildMultiEntryTimeline(
        from cached: CachedWeatherData,
        conditionTag: WeatherConditionTag,
        entity: LocationEntity
    ) -> [WeatherWidgetEntry] {
        let allPhrases = cached.allPhrases
        let forecast = Self.convertForecastPoints(from: cached)
        let now = Date()
        let smallFallback = cached.smallPhrase ?? cached.phrase
        let displayName = cached.locationName.isEmpty ? entity.name : cached.locationName

        return (0..<4).map { offset in
            let entryDate = Calendar.current.date(byAdding: .minute, value: offset * 4, to: now) ?? now
            let rotatedPhrase: String = {
                guard !allPhrases.isEmpty else { return cached.phrase }
                return allPhrases[offset % allPhrases.count]
            }()
            return WeatherWidgetEntry(
                date: entryDate,
                temperature: Int(cached.temperature.rounded()),
                conditionTag: conditionTag,
                conditionLabel: cached.conditionLabel,
                isDay: cached.isDay,
                phrase: rotatedPhrase,
                smallPhrase: smallFallback,
                feelsLike: Int(cached.feelsLike.rounded()),
                high: Int(cached.high.rounded()),
                low: Int(cached.low.rounded()),
                precipProbability: 0,
                hourlyPreview: forecast.hourly,
                dailyPreview: forecast.daily,
                locationName: displayName,
                isDeviceLocation: entity.isMyLocation
            )
        }
    }

    /// Convert cached hourly/daily forecast data to widget entry types.
    private static func convertForecastPoints(from cached: CachedWeatherData) -> (
        hourly: [WeatherWidgetEntry.HourlyWidgetPoint],
        daily: [WeatherWidgetEntry.DailyWidgetPoint]
    ) {
        let hourly = cached.hourlyPreview.compactMap { point -> WeatherWidgetEntry.HourlyWidgetPoint? in
            guard let tag = WeatherConditionTag(rawValue: point.conditionTag) else { return nil }
            return WeatherWidgetEntry.HourlyWidgetPoint(hour: point.hour, temp: point.temp, conditionTag: tag, isDay: point.isDay)
        }
        let daily = cached.dailyPreview.compactMap { point -> WeatherWidgetEntry.DailyWidgetPoint? in
            guard let tag = WeatherConditionTag(rawValue: point.conditionTag) else { return nil }
            return WeatherWidgetEntry.DailyWidgetPoint(day: point.day, high: point.high, low: point.low, conditionTag: tag)
        }
        return (hourly, daily)
    }

    // MARK: - Fresh-fetch cache write

    private func saveFreshDataToMultiCache(
        _ entry: WeatherWidgetEntry,
        additionalPhrases: [String] = [],
        for entity: LocationEntity
    ) {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"

        let cachedHourly = entry.hourlyPreview.map { h in
            CachedHourlyPoint(hour: h.hour, temp: h.temp, conditionTag: h.conditionTag.rawValue, isDay: h.isDay)
        }
        let cachedDaily = entry.dailyPreview.map { d in
            CachedDailyPoint(day: d.day, high: d.high, low: d.low, conditionTag: d.conditionTag.rawValue)
        }

        WidgetDataStore.saveEntry(
            CachedWeatherData(
                temperature: Double(entry.temperature),
                conditionTag: entry.conditionTag.rawValue,
                conditionLabel: entry.conditionLabel,
                isDay: entry.isDay,
                feelsLike: Double(entry.feelsLike),
                high: Double(entry.high),
                low: Double(entry.low),
                locationName: entry.locationName,
                phrase: entry.phrase,
                phraseMode: modeStr,
                additionalPhrases: additionalPhrases,
                smallPhrase: entry.smallPhrase,
                hourlyPreview: cachedHourly,
                dailyPreview: cachedDaily
            ),
            for: entity.id
        )
    }

    // MARK: - Fresh WeatherKit fetch

    /// Resolve the configured `LocationEntity` into a `CLLocation`, fetch
    /// WeatherKit + NWS/METAR consensus, and build a widget entry. Used both
    /// when the multi-cache is cold AND for background refresh after a cache
    /// hit. Each widget refresh does its own fetch; the `ObservationCrossCheckService`
    /// persisted disk cache prevents duplicate NWS/METAR hits across processes.
    private func fetchFreshEntry(for entity: LocationEntity) async throws -> WeatherWidgetEntry {
        let location: CLLocation
        let displayName: String

        if entity.isMyLocation {
            if let fresh = await locationProvider.currentLocation() {
                location = fresh
                displayName = await reverseGeocodedCityName(for: fresh) ?? "Current Location"
            } else if let cachedLocation = CLLocationManager().location {
                // Last-resort: iOS-level cached location.
                location = cachedLocation
                displayName = await reverseGeocodedCityName(for: cachedLocation) ?? "Current Location"
            } else {
                throw WidgetError.noLocation
            }
        } else if let lat = entity.latitude, let lon = entity.longitude {
            location = CLLocation(latitude: lat, longitude: lon)
            displayName = entity.name
        } else {
            // LocationEntity has no coords — typically the case when a saved
            // city was deleted. Fall back to My Location.
            widgetProviderLog.warning("entity has no coords, falling back to My Location: \(entity.id, privacy: .public)")
            return try await fetchFreshEntry(for: .myLocation)
        }

        let service = WeatherKit.WeatherService.shared
        async let wkTask = service.weather(
            for: location,
            including: .current, .hourly, .daily
        )
        async let consensusTask = Self.crossCheck.fetchSkyConsensus(for: location)

        let weather = try await wkTask
        let consensus = await consensusTask

        let current = weather.0
        let hourly = weather.1
        let daily = weather.2

        let windMph = current.wind.speed.converted(to: .milesPerHour).value
        let baseTag = WeatherConditionTag.from(current.condition, windSpeed: windMph)
        let conditionTag = applyConsensusOverride(
            base: baseTag,
            consensus: consensus,
            wkCloudCoverPct: current.cloudCover * 100
        )
        let conditionLabel = (conditionTag != baseTag)
            ? conditionTag.label
            : current.condition.description
        let tempF = current.temperature.converted(to: .fahrenheit).value

        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
        let mode = PhraseMode(rawValue: modeStr) ?? .clean

        let phrase = await phraseEngine.selectPhrase(
            conditionTag: conditionTag,
            tempF: tempF,
            mode: mode,
            isDay: current.isDaylight
        )

        // Get DST-aware timezone via reverse geocoding
        let locationTimezone: TimeZone
        if #available(iOS 26, *) {
            if let request = MKReverseGeocodingRequest(location: location),
               let tz = try? await request.mapItems.first?.timeZone {
                locationTimezone = tz
            } else {
                locationTimezone = .current
            }
        } else {
            if let tz = try? await CLGeocoder().reverseGeocodeLocation(location).first?.timeZone {
                locationTimezone = tz
            } else {
                locationTimezone = .current
            }
        }

        // Filter to current hour and forward — WeatherKit returns past hours too
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let filteredHourly = hourly.filter { $0.date >= currentHourStart }

        let hourlyPreview = Array(filteredHourly.prefix(6)).enumerated().map { index, h in
            WeatherWidgetEntry.HourlyWidgetPoint(
                hour: index == 0 ? "Now" : h.date.hourLabel(timezone: locationTimezone),
                temp: Int(h.temperature.converted(to: .fahrenheit).value.rounded()),
                conditionTag: WeatherConditionTag.from(h.condition),
                isDay: h.isDaylight
            )
        }

        let dailyPreview = Array(daily.prefix(5)).enumerated().map { index, d in
            WeatherWidgetEntry.DailyWidgetPoint(
                day: d.date.dayLabel(index: index, timezone: locationTimezone),
                high: Int(d.highTemperature.converted(to: .fahrenheit).value.rounded()),
                low: Int(d.lowTemperature.converted(to: .fahrenheit).value.rounded()),
                conditionTag: WeatherConditionTag.from(d.condition)
            )
        }

        let todayHigh = daily.first.map { Int($0.highTemperature.converted(to: .fahrenheit).value.rounded()) } ?? 0
        let todayLow = daily.first.map { Int($0.lowTemperature.converted(to: .fahrenheit).value.rounded()) } ?? 0

        let smallPhrase = await phraseEngine.selectPhrase(
            conditionTag: conditionTag,
            tempF: tempF,
            mode: mode,
            isDay: current.isDaylight,
            maxLength: 70
        )

        return WeatherWidgetEntry(
            date: Date(),
            temperature: Int(tempF.rounded()),
            conditionTag: conditionTag,
            conditionLabel: conditionLabel,
            isDay: current.isDaylight,
            phrase: phrase,
            smallPhrase: smallPhrase,
            feelsLike: Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
            high: todayHigh,
            low: todayLow,
            precipProbability: Int((daily.first?.precipitationChance ?? 0) * 100),
            hourlyPreview: hourlyPreview,
            dailyPreview: dailyPreview,
            locationName: displayName,
            isDeviceLocation: entity.isMyLocation
        )
    }

    /// Reverse-geocode a coordinate to a user-visible city label like "Seattle, WA".
    ///
    /// Critical: `MKMapItem.name` can return a street address, POI, or business —
    /// NOT the city. Prefer `addressRepresentations?.cityWithContext(.short)` for
    /// "City, ST" formatting, then `cityName`, and only fall through to `.name`
    /// when nothing else is available.
    private func reverseGeocodedCityName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let items = try? await request.mapItems,
              let item = items.first else {
            return nil
        }
        if let withContext = item.addressRepresentations?.cityWithContext(.short),
           !withContext.isEmpty {
            return withContext
        }
        if let city = item.addressRepresentations?.cityName, !city.isEmpty {
            return city
        }
        if let name = item.name, !name.isEmpty {
            return name
        }
        return nil
    }
}

enum WidgetError: Error {
    case noLocation
}
