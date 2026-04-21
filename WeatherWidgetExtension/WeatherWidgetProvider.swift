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
    /// saved city the user selected in-app.
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

struct WeatherWidgetProvider: TimelineProvider {
    private let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )

    /// Held as an instance property so its CLLocationManager delegate survives
    /// past the getTimeline / fetchWeatherEntry async call stack. iOS reloads
    /// this widget's timeline automatically when the device's significant
    /// location changes (enabled via NSWidgetWantsLocation in Info.plist).
    private let locationProvider = WidgetLocationProvider()

    // MARK: - Shared Conversion Helpers

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

    func placeholder(in context: Context) -> WeatherWidgetEntry {
        // WidgetKit calls this on a very tight budget — any disk I/O risks
        // skipping the first render. Return the hardcoded placeholder only;
        // real cached data is served from getSnapshot / getTimeline.
        widgetProviderLog.info("placeholder(in:) called")
        return .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        widgetProviderLog.info("getSnapshot called, isPreview=\(context.isPreview)")
        // Try cached data first — pure file/UserDefaults reads, completes in milliseconds.
        if let cached = buildCachedEntry() {
            widgetProviderLog.info("getSnapshot: returning cached entry, temp=\(cached.temperature)")
            completion(cached)
            return
        }

        widgetProviderLog.warning("getSnapshot: no cached data, trying async fetch")
        // No cached data (app never opened) — try live WeatherKit fetch
        Task {
            if let entry = try? await fetchWeatherEntry() {
                widgetProviderLog.info("getSnapshot: async fetch succeeded")
                completion(entry)
                return
            }
            // Absolute last resort — hardcoded placeholder
            widgetProviderLog.error("getSnapshot: ALL sources failed, returning placeholder")
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        widgetProviderLog.info("getTimeline called")
        widgetProviderLog.info("getTimeline: diagnose = \(WidgetDataStore.diagnose())")
        // Call completion synchronously with cached data — WidgetKit kills extensions that go async.
        if let cachedData = WidgetDataStore.load(),
           let conditionTag = WeatherConditionTag(rawValue: cachedData.conditionTag),
           !isCachedDataStale(cachedData: cachedData) {
            widgetProviderLog.info("getTimeline PATH 1: JSON load succeeded, temp=\(cachedData.temperature) location=\(cachedData.locationName)")

            // Build multi-entry timeline using the pre-generated phrases the app wrote.
            // 4 entries at ~4-minute intervals give the user phrase variety without
            // WidgetKit refetching; temperature/condition stay constant within the window.
            let allPhrases = cachedData.allPhrases
            let forecast = Self.convertForecastPoints(from: cachedData)
            let now = Date()
            let smallFallback = cachedData.smallPhrase ?? cachedData.phrase

            let entries: [WeatherWidgetEntry] = (0..<4).map { offset in
                let entryDate = Calendar.current.date(byAdding: .minute, value: offset * 4, to: now) ?? now
                let rotatedPhrase: String = {
                    guard !allPhrases.isEmpty else { return cachedData.phrase }
                    return allPhrases[offset % allPhrases.count]
                }()
                return WeatherWidgetEntry(
                    date: entryDate,
                    temperature: Int(cachedData.temperature.rounded()),
                    conditionTag: conditionTag,
                    conditionLabel: cachedData.conditionLabel,
                    isDay: cachedData.isDay,
                    phrase: rotatedPhrase,
                    smallPhrase: smallFallback,
                    feelsLike: Int(cachedData.feelsLike.rounded()),
                    high: Int(cachedData.high.rounded()),
                    low: Int(cachedData.low.rounded()),
                    precipProbability: 0,
                    hourlyPreview: forecast.hourly,
                    dailyPreview: forecast.daily,
                    locationName: cachedData.locationName,
                    isDeviceLocation: currentDeviceModeFlag()
                )
            }

            // Request refresh in 15 minutes — matches industry standard for weather apps.
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: entries, policy: .after(nextUpdate)))

            // Background: fetch fresh weather + new phrases and save for next cycle
            Task { await refreshCachedData() }
            return
        }

        // Fallback: try UserDefaults-based cached entry
        widgetProviderLog.warning("getTimeline: JSON load failed, trying UserDefaults fallback")
        if let cached = buildCachedEntry() {
            widgetProviderLog.info("getTimeline PATH 2: UserDefaults fallback succeeded")
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [cached], policy: .after(nextUpdate)))
            Task { await refreshCachedData() }
            return
        }

        // No cached data (app never opened) — try async fetch as last resort.
        widgetProviderLog.error("getTimeline PATH 3: No cached data at all, trying async fetch")
        Task {
            if let entry = try? await fetchWeatherEntry() {
                saveFreshDataToCache(entry)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            } else {
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
                completion(Timeline(entries: [.placeholder], policy: .after(nextUpdate)))
            }
        }
    }

    /// Build an entry from cached weather data the main app wrote to the shared container.
    /// Uses file-based sharing (reliable cross-process) with UserDefaults as fallback.
    /// Returns nil if no cached data exists (app has never fetched weather).
    private func buildCachedEntry() -> WeatherWidgetEntry? {
        // PRIMARY: Read from shared JSON file — reliable cross-process on iPhone
        if let cached = WidgetDataStore.load(),
           let conditionTag = WeatherConditionTag(rawValue: cached.conditionTag) {
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
                locationName: cached.locationName,
                isDeviceLocation: currentDeviceModeFlag()
            )
        }

        // FALLBACK: Try UserDefaults (may not have synced cross-process yet)
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.synchronize()

        guard let conditionRaw = defaults.string(forKey: AppConstants.UserDefaultsKeys.cachedConditionTag),
              let conditionTag = WeatherConditionTag(rawValue: conditionRaw) else {
            return nil
        }

        let cachedTemp = defaults.double(forKey: AppConstants.UserDefaultsKeys.cachedTemperature)
        let temperature = Int(cachedTemp.rounded())
        let conditionLabel = defaults.string(forKey: AppConstants.UserDefaultsKeys.cachedConditionLabel) ?? conditionTag.label
        let isDay = defaults.bool(forKey: AppConstants.UserDefaultsKeys.cachedIsDay)
        let feelsLike = Int(defaults.double(forKey: AppConstants.UserDefaultsKeys.cachedFeelsLike).rounded())
        let high = Int(defaults.double(forKey: AppConstants.UserDefaultsKeys.cachedHigh).rounded())
        let low = Int(defaults.double(forKey: AppConstants.UserDefaultsKeys.cachedLow).rounded())
        let locationName = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastLocationName) ?? "Unknown"
        let phrase = defaults.string(forKey: AppConstants.UserDefaultsKeys.currentPhrase) ?? "\(conditionLabel) and \(temperature)°."

        return WeatherWidgetEntry(
            date: Date(),
            temperature: temperature,
            conditionTag: conditionTag,
            conditionLabel: conditionLabel,
            isDay: isDay,
            phrase: phrase,
            smallPhrase: phrase,
            feelsLike: feelsLike,
            high: high,
            low: low,
            precipProbability: 0,
            hourlyPreview: WeatherWidgetEntry.placeholder.hourlyPreview,
            dailyPreview: WeatherWidgetEntry.placeholder.dailyPreview,
            locationName: locationName,
            isDeviceLocation: currentDeviceModeFlag()
        )
    }

    /// Reads the app-set flag indicating whether the widget should show the
    /// device's current GPS location (true) vs. a user-pinned city (false).
    /// Defaults to true when absent so first-ever installs behave as
    /// "current location" widgets — matches the Apple Weather default.
    private func currentDeviceModeFlag() -> Bool {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.synchronize()
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.lastLocationIsCurrentDevice) == nil {
            return true
        }
        return defaults.bool(forKey: AppConstants.UserDefaultsKeys.lastLocationIsCurrentDevice)
    }

    /// Detect whether the JSON cache is out of date relative to UserDefaults.
    /// If the app just cycled to a new city, `writeWidgetIdentity` updates
    /// UserDefaults immediately but the JSON write is async and may lag. When
    /// that happens, serving the stale JSON would display the wrong city —
    /// so we skip PATH 1 and fall through to PATH 3 (fresh fetch) instead.
    private func isCachedDataStale(cachedData: CachedWeatherData) -> Bool {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.synchronize()
        guard let expectedName = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastLocationName),
              !expectedName.isEmpty else {
            return false
        }
        let isStale = cachedData.locationName != expectedName
        if isStale {
            widgetProviderLog.info("getTimeline: cache stale — JSON=\(cachedData.locationName, privacy: .public) vs UserDefaults=\(expectedName, privacy: .public); skipping PATH 1")
        }
        return isStale
    }

    /// Fetch fresh weather + phrases in the background and save to cache.
    /// The current widget cycle already has cached data displayed — this updates the
    /// cache so the NEXT timeline cycle shows fresh data with new phrases.
    private func refreshCachedData() async {
        guard let entry = try? await fetchWeatherEntry() else { return }

        // Pre-generate additional phrases for the next multi-entry timeline.
        // selectPhrase() always generates a new phrase (has anti-repeat logic).
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
        let mode = PhraseMode(rawValue: modeStr) ?? .clean

        let extraPhrases = await phraseEngine.selectMultiplePhrases(
            count: 3,
            conditionTag: entry.conditionTag,
            tempF: Double(entry.temperature),
            mode: mode,
            isDay: entry.isDay
        )

        saveFreshDataToCache(entry, additionalPhrases: extraPhrases)
    }

    /// Write a fresh entry's data to the shared container so buildCachedEntry() returns
    /// updated values on the next timeline refresh.
    private func saveFreshDataToCache(_ entry: WeatherWidgetEntry, additionalPhrases: [String] = []) {
        // Write to shared JSON file (primary, reliable)
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"

        // Convert entry's hourly/daily preview to cached format
        let cachedHourly = entry.hourlyPreview.map { h in
            CachedHourlyPoint(hour: h.hour, temp: h.temp, conditionTag: h.conditionTag.rawValue, isDay: h.isDay)
        }
        let cachedDaily = entry.dailyPreview.map { d in
            CachedDailyPoint(day: d.day, high: d.high, low: d.low, conditionTag: d.conditionTag.rawValue)
        }

        WidgetDataStore.save(CachedWeatherData(
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
        ))

        // Also write to UserDefaults as fallback
        defaults.set(Double(entry.temperature), forKey: AppConstants.UserDefaultsKeys.cachedTemperature)
        defaults.set(entry.conditionTag.rawValue, forKey: AppConstants.UserDefaultsKeys.cachedConditionTag)
        defaults.set(entry.conditionLabel, forKey: AppConstants.UserDefaultsKeys.cachedConditionLabel)
        defaults.set(entry.isDay, forKey: AppConstants.UserDefaultsKeys.cachedIsDay)
        defaults.set(Double(entry.feelsLike), forKey: AppConstants.UserDefaultsKeys.cachedFeelsLike)
        defaults.set(Double(entry.high), forKey: AppConstants.UserDefaultsKeys.cachedHigh)
        defaults.set(Double(entry.low), forKey: AppConstants.UserDefaultsKeys.cachedLow)
        defaults.set(entry.phrase, forKey: AppConstants.UserDefaultsKeys.currentPhrase)
        defaults.set(entry.locationName, forKey: AppConstants.UserDefaultsKeys.lastLocationName)
        defaults.synchronize()
    }

    private func fetchWeatherEntry() async throws -> WeatherWidgetEntry {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        // Force cross-process sync so we pick up data the main app just wrote
        defaults.synchronize()
        let savedLat = defaults.double(forKey: AppConstants.UserDefaultsKeys.lastLocationLat)
        let savedLon = defaults.double(forKey: AppConstants.UserDefaultsKeys.lastLocationLon)
        let savedName = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastLocationName) ?? "Unknown"
        let isCurrentDeviceMode = currentDeviceModeFlag()

        // LOCATION RESOLUTION branches on the mode flag written by the main app:
        //  - Current-location mode (user was on the "My Location" page): fetch
        //    fresh device GPS so the widget auto-updates when the user travels
        //    (via NSWidgetWantsLocation's significant-location-change reload).
        //  - Pinned-city mode (user selected a saved city in-app): use exactly
        //    the coords and name the app wrote. No GPS, no reverse-geocode —
        //    the widget should stay on that city until the user changes it
        //    in-app, matching Apple Weather's per-widget-pin behavior.
        let location: CLLocation
        let locationName: String
        if isCurrentDeviceMode, let fresh = await locationProvider.currentLocation() {
            location = fresh
            // If the user has moved far enough that the app-saved name is stale,
            // reverse-geocode a fresh name. Otherwise keep the app-saved name.
            let savedLocation = CLLocation(latitude: savedLat, longitude: savedLon)
            let distance = (savedLat != 0 || savedLon != 0)
                ? fresh.distance(from: savedLocation)
                : .greatestFiniteMagnitude
            if distance > 10_000 {
                locationName = await reverseGeocodedCityName(for: fresh) ?? savedName
            } else {
                locationName = savedName
            }
        } else if savedLat != 0 || savedLon != 0 {
            // Pinned-city mode OR GPS unavailable: trust the app-written coords+name.
            location = CLLocation(latitude: savedLat, longitude: savedLon)
            locationName = savedName
        } else if isCurrentDeviceMode, let cachedLocation = CLLocationManager().location {
            // Last-resort only in current-location mode: iOS-level cached location.
            location = cachedLocation
            locationName = await reverseGeocodedCityName(for: cachedLocation) ?? "Current Location"
        } else {
            throw WidgetError.noLocation
        }

        // Fetch WeatherKit + NWS + METAR in parallel. The cross-check service is
        // short-lived (one widget invocation) — no persistent cache across refreshes,
        // but this fallback path only runs when the main-app cache is empty.
        let service = WeatherKit.WeatherService.shared
        let crossCheck = ObservationCrossCheckService()
        async let wkTask = service.weather(
            for: location,
            including: .current, .hourly, .daily
        )
        async let consensusTask = crossCheck.fetchSkyConsensus(for: location)

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

        // Always generate a fresh phrase. selectPhrase() calls loadIfNeeded() internally,
        // so it handles PhraseEngine initialization. This runs after completion() has
        // already been called, so taking a moment to load JSON is fine.
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

        // Generate a shorter phrase for the small widget
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
            locationName: locationName,
            isDeviceLocation: isCurrentDeviceMode
        )
    }

    /// Reverse-geocode a coordinate to a user-visible city label like "Seattle, WA".
    ///
    /// Critical: `MKMapItem.name` can return a street address, POI, or business —
    /// NOT the city. Prefer `addressRepresentations?.cityWithContext(.short)` for
    /// "City, ST" formatting, then `cityName`, and only fall through to `.name`
    /// when nothing else is available. Caller treats a nil return as a soft-fail
    /// and keeps whatever name it already had.
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
