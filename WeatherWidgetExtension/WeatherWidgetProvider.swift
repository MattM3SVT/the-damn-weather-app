import WidgetKit
import WeatherKit
import CoreLocation
import MapKit
import WeatherShared

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
            locationName: ""
        )
    }
}

struct WeatherWidgetProvider: TimelineProvider {
    private let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )

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
        // Use cached data so widget shows real weather immediately on iPhone.
        buildCachedEntry() ?? .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        // Try cached data first — pure file/UserDefaults reads, completes in milliseconds.
        if let cached = buildCachedEntry() {
            completion(cached)
            return
        }

        // No cached data (app never opened) — try live WeatherKit fetch
        Task {
            if let entry = try? await fetchWeatherEntry() {
                completion(entry)
                return
            }
            // Absolute last resort — hardcoded placeholder
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        // Call completion synchronously with cached data — WidgetKit kills extensions that go async.
        if let cachedData = WidgetDataStore.load(),
           let conditionTag = WeatherConditionTag(rawValue: cachedData.conditionTag) {

            // Build multi-entry timeline: one entry per 15 minutes using pre-generated phrases.
            // The main app pre-generates 4 phrases so the widget shows variety without
            // needing PhraseEngine (which requires loading 728KB of JSON in the extension).
            let allPhrases = cachedData.allPhrases

            // Convert cached forecast data to widget entry types
            let hourlyPoints: [WeatherWidgetEntry.HourlyWidgetPoint] = cachedData.hourlyPreview.compactMap { point in
                guard let tag = WeatherConditionTag(rawValue: point.conditionTag) else { return nil }
                return WeatherWidgetEntry.HourlyWidgetPoint(
                    hour: point.hour, temp: point.temp, conditionTag: tag, isDay: point.isDay
                )
            }
            let dailyPoints: [WeatherWidgetEntry.DailyWidgetPoint] = cachedData.dailyPreview.compactMap { point in
                guard let tag = WeatherConditionTag(rawValue: point.conditionTag) else { return nil }
                return WeatherWidgetEntry.DailyWidgetPoint(
                    day: point.day, high: point.high, low: point.low, conditionTag: tag
                )
            }

            // Single entry per timeline — WidgetKit refreshes every 15 minutes,
            // fetching fresh weather data + a new phrase each cycle.
            // Pick a random phrase from the pre-generated set for variety.
            let phrase = allPhrases.randomElement() ?? cachedData.phrase

            let entry = WeatherWidgetEntry(
                date: Date(),
                temperature: Int(cachedData.temperature.rounded()),
                conditionTag: conditionTag,
                conditionLabel: cachedData.conditionLabel,
                isDay: cachedData.isDay,
                phrase: phrase,
                smallPhrase: cachedData.smallPhrase ?? phrase,
                feelsLike: Int(cachedData.feelsLike.rounded()),
                high: Int(cachedData.high.rounded()),
                low: Int(cachedData.low.rounded()),
                precipProbability: 0,
                hourlyPreview: hourlyPoints,
                dailyPreview: dailyPoints,
                locationName: cachedData.locationName
            )

            // Request refresh in 15 minutes — matches industry standard for weather apps.
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))

            // Background: fetch fresh weather + new phrases and save for next cycle
            Task { await refreshCachedData() }
            return
        }

        // Fallback: try UserDefaults-based cached entry
        if let cached = buildCachedEntry() {
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [cached], policy: .after(nextUpdate)))
            Task { await refreshCachedData() }
            return
        }

        // No cached data (app never opened) — try async fetch as last resort.
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
            let hourlyPoints: [WeatherWidgetEntry.HourlyWidgetPoint] = cached.hourlyPreview.compactMap { point in
                guard let tag = WeatherConditionTag(rawValue: point.conditionTag) else { return nil }
                return WeatherWidgetEntry.HourlyWidgetPoint(
                    hour: point.hour, temp: point.temp, conditionTag: tag, isDay: point.isDay
                )
            }
            let dailyPoints: [WeatherWidgetEntry.DailyWidgetPoint] = cached.dailyPreview.compactMap { point in
                guard let tag = WeatherConditionTag(rawValue: point.conditionTag) else { return nil }
                return WeatherWidgetEntry.DailyWidgetPoint(
                    day: point.day, high: point.high, low: point.low, conditionTag: tag
                )
            }
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
                hourlyPreview: hourlyPoints,
                dailyPreview: dailyPoints,
                locationName: cached.locationName
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
            locationName: locationName
        )
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
        let lat = defaults.double(forKey: AppConstants.UserDefaultsKeys.lastLocationLat)
        let lon = defaults.double(forKey: AppConstants.UserDefaultsKeys.lastLocationLon)
        let locationName = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastLocationName) ?? "Unknown"

        let location: CLLocation
        if lat != 0 || lon != 0 {
            location = CLLocation(latitude: lat, longitude: lon)
        } else if let cachedLocation = CLLocationManager().location {
            // Use system's cached last-known location as fallback
            location = cachedLocation
        } else {
            throw WidgetError.noLocation
        }

        let service = WeatherKit.WeatherService.shared
        let weather = try await service.weather(
            for: location,
            including: .current, .hourly, .daily
        )

        let current = weather.0
        let hourly = weather.1
        let daily = weather.2

        let windMph = current.wind.speed.converted(to: .milesPerHour).value
        let conditionTag = WeatherConditionTag.from(current.condition, windSpeed: windMph)
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
            conditionLabel: current.condition.description,
            isDay: current.isDaylight,
            phrase: phrase,
            smallPhrase: smallPhrase,
            feelsLike: Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
            high: todayHigh,
            low: todayLow,
            precipProbability: Int((daily.first?.precipitationChance ?? 0) * 100),
            hourlyPreview: hourlyPreview,
            dailyPreview: dailyPreview,
            locationName: locationName
        )
    }
}

enum WidgetError: Error {
    case noLocation
}
