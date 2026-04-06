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
    let feelsLike: Int
    let high: Int
    let low: Int
    let precipProbability: Int
    let hourlyPreview: [HourlyWidgetPoint]
    let dailyPreview: [DailyWidgetPoint]
    let locationName: String

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
        // DEBUG: Check what's accessible from widget extension
        let hasContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) != nil
        let hasFile = WidgetDataStore.load() != nil
        let suiteDefaults = UserDefaults(suiteName: AppConstants.appGroupID)
        let hasDefaults = suiteDefaults?.string(forKey: AppConstants.UserDefaultsKeys.cachedConditionTag) != nil
        let debugInfo = "F:\(hasFile) C:\(hasContainer) D:\(hasDefaults)"

        let defaults = suiteDefaults ?? .standard
        let savedName = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastLocationName)
        let locationName = savedName?.isEmpty == false ? savedName ?? "Your Location" : "Your Location"

        return WeatherWidgetEntry(
            date: Date(),
            temperature: 72,
            conditionTag: .partlyCloudy,
            conditionLabel: "Partly Cloudy",
            isDay: true,
            phrase: "[\(debugInfo)] Open app to load weather.",
            feelsLike: 70,
            high: 78,
            low: 62,
            precipProbability: 10,
            hourlyPreview: (0..<6).map { i in
                let tags: [WeatherConditionTag] = [.partlyCloudy, .clear, .partlyCloudy, .cloudy, .clear, .partlyCloudy]
                return .init(hour: i == 0 ? "Now" : "\(i + 1) PM", temp: 72 + i, conditionTag: tags[i], isDay: true)
            },
            dailyPreview: [
                .init(day: "Today", high: 78, low: 62, conditionTag: .partlyCloudy),
                .init(day: "Tue", high: 75, low: 58, conditionTag: .clear),
                .init(day: "Wed", high: 68, low: 55, conditionTag: .rain),
                .init(day: "Thu", high: 72, low: 57, conditionTag: .cloudy),
                .init(day: "Fri", high: 80, low: 63, conditionTag: .clear),
            ],
            locationName: locationName
        )
    }
}

struct WeatherWidgetProvider: TimelineProvider {
    private let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )

    func placeholder(in context: Context) -> WeatherWidgetEntry {
        // On iPhone, WidgetKit may show placeholder() for longer before calling getTimeline().
        // Use cached data here too so the user sees real weather immediately.
        if let cached = buildCachedEntry() {
            // Tag with PH: so we know this came from placeholder()
            return WeatherWidgetEntry(
                date: cached.date,
                temperature: cached.temperature,
                conditionTag: cached.conditionTag,
                conditionLabel: cached.conditionLabel,
                isDay: cached.isDay,
                phrase: "PH: " + cached.phrase,
                feelsLike: cached.feelsLike,
                high: cached.high,
                low: cached.low,
                precipProbability: cached.precipProbability,
                hourlyPreview: cached.hourlyPreview,
                dailyPreview: cached.dailyPreview,
                locationName: cached.locationName
            )
        }
        return .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        // Try cached data first — pure file/UserDefaults reads, completes in milliseconds.
        if let cached = buildCachedEntry() {
            let entry = WeatherWidgetEntry(
                date: cached.date,
                temperature: cached.temperature,
                conditionTag: cached.conditionTag,
                conditionLabel: cached.conditionLabel,
                isDay: cached.isDay,
                phrase: "SS: " + cached.phrase,
                feelsLike: cached.feelsLike,
                high: cached.high,
                low: cached.low,
                precipProbability: cached.precipProbability,
                hourlyPreview: cached.hourlyPreview,
                dailyPreview: cached.dailyPreview,
                locationName: cached.locationName
            )
            completion(entry)
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
        // buildCachedEntry() now ALWAYS returns an entry (diagnostic if data fails).
        // Call completion synchronously — WidgetKit kills extensions that go async.
        let cached = buildCachedEntry()
        if let cached {
            // Prepend TL: so we know this came from getTimeline, not placeholder
            let entry = WeatherWidgetEntry(
                date: cached.date,
                temperature: cached.temperature,
                conditionTag: cached.conditionTag,
                conditionLabel: cached.conditionLabel,
                isDay: cached.isDay,
                phrase: "TL: " + cached.phrase,
                feelsLike: cached.feelsLike,
                high: cached.high,
                low: cached.low,
                precipProbability: cached.precipProbability,
                hourlyPreview: cached.hourlyPreview,
                dailyPreview: cached.dailyPreview,
                locationName: cached.locationName
            )
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))

            // Background: fetch fresh weather + phrase and save for next refresh
            Task { await refreshCachedData() }
            return
        }

        // Should never reach here now — buildCachedEntry returns diagnostic entries instead of nil.
        // But keep as safety net.
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
        let fileData = WidgetDataStore.load()
        if let cached = fileData {
            let conditionTag = WeatherConditionTag(rawValue: cached.conditionTag)
            if let conditionTag {
                return WeatherWidgetEntry(
                    date: Date(),
                    temperature: Int(cached.temperature.rounded()),
                    conditionTag: conditionTag,
                    conditionLabel: cached.conditionLabel,
                    isDay: cached.isDay,
                    phrase: cached.phrase,
                    feelsLike: Int(cached.feelsLike.rounded()),
                    high: Int(cached.high.rounded()),
                    low: Int(cached.low.rounded()),
                    precipProbability: 0,
                    hourlyPreview: WeatherWidgetEntry.placeholder.hourlyPreview,
                    dailyPreview: WeatherWidgetEntry.placeholder.dailyPreview,
                    locationName: cached.locationName
                )
            } else {
                // DEBUG: File loaded but conditionTag rawValue didn't match enum
                return makeDiagnosticEntry("FILE_OK tag_FAIL rawVal='\(cached.conditionTag)' temp=\(cached.temperature)")
            }
        }

        // FALLBACK: Try UserDefaults (may not have synced cross-process yet)
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.synchronize()

        let conditionRaw = defaults.string(forKey: AppConstants.UserDefaultsKeys.cachedConditionTag)
        guard let conditionRaw else {
            // DEBUG: Neither file nor UserDefaults had data
            let fileURLExists = WidgetDataStore.debugFileExists()
            return makeDiagnosticEntry("NO_DATA file=\(fileData != nil) fileURL=\(fileURLExists)")
        }

        let conditionTag = WeatherConditionTag(rawValue: conditionRaw)
        guard let conditionTag else {
            return makeDiagnosticEntry("UD_TAG_FAIL rawVal='\(conditionRaw)'")
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
            feelsLike: feelsLike,
            high: high,
            low: low,
            precipProbability: 0,
            hourlyPreview: WeatherWidgetEntry.placeholder.hourlyPreview,
            dailyPreview: WeatherWidgetEntry.placeholder.dailyPreview,
            locationName: locationName
        )
    }

    /// Creates a diagnostic entry so we can see exactly what failed on the widget face
    private func makeDiagnosticEntry(_ info: String) -> WeatherWidgetEntry {
        WeatherWidgetEntry(
            date: Date(),
            temperature: 0,
            conditionTag: .clear,
            conditionLabel: "Debug",
            isDay: true,
            phrase: "DBG: \(info)",
            feelsLike: 0,
            high: 0,
            low: 0,
            precipProbability: 0,
            hourlyPreview: [],
            dailyPreview: [],
            locationName: "Diagnostics"
        )
    }

    /// Fetch fresh weather + phrase in the background and save to UserDefaults.
    /// The current widget cycle already has cached data displayed — this updates the
    /// cache so the NEXT 15-min refresh shows fresh data.
    private func refreshCachedData() async {
        guard let entry = try? await fetchWeatherEntry() else { return }
        saveFreshDataToCache(entry)
    }

    /// Write a fresh entry's data to shared UserDefaults so buildCachedEntry() returns
    /// updated values on the next timeline refresh.
    private func saveFreshDataToCache(_ entry: WeatherWidgetEntry) {
        // Write to shared JSON file (primary, reliable)
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"

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
            phraseMode: modeStr
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

        // Start PhraseEngine warmup concurrently — it loads 728KB of JSON from disk,
        // which runs in parallel with the WeatherKit network call below.
        // By the time WeatherKit returns (~2-5s), PhraseEngine is almost always ready.
        Task { [phraseEngine] in await phraseEngine.warmUp() }

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

        // Generate a fresh phrase if PhraseEngine is ready (warmed up during WeatherKit fetch).
        // If still loading (rare — only on very slow disk I/O), use the cached phrase.
        let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
        let mode = PhraseMode(rawValue: modeStr) ?? .clean

        let phrase: String
        if phraseEngine.isReady {
            phrase = await phraseEngine.selectPhrase(
                conditionTag: conditionTag,
                tempF: tempF,
                mode: mode,
                isDay: current.isDaylight
            )
        } else {
            phrase = defaults.string(forKey: AppConstants.UserDefaultsKeys.currentPhrase)
                ?? "\(conditionTag.label) and \(Int(tempF.rounded()))°."
        }

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

        return WeatherWidgetEntry(
            date: Date(),
            temperature: Int(tempF.rounded()),
            conditionTag: conditionTag,
            conditionLabel: current.condition.description,
            isDay: current.isDaylight,
            phrase: phrase,
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
