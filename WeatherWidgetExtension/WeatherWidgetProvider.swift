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
        // Use the user's last known location name if available
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let savedName = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastLocationName)
        let locationName = savedName?.isEmpty == false ? savedName ?? "Your Location" : "Your Location"

        return WeatherWidgetEntry(
            date: Date(),
            temperature: 72,
            conditionTag: .partlyCloudy,
            conditionLabel: "Partly Cloudy",
            isDay: true,
            phrase: "72° and partly cloudy. Nature's way of saying \"meh.\"",
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
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        Task {
            // Try to show real weather data if location is available
            if let entry = try? await fetchWeatherEntry() {
                completion(entry)
                return
            }

            // Fall back to placeholder with a real phrase
            let phrase = await phraseEngine.selectPhrase(
                conditionTag: .partlyCloudy,
                tempF: 72,
                mode: .clean,
                isDay: true
            )
            let entry = WeatherWidgetEntry.placeholder
            let snapshotEntry = WeatherWidgetEntry(
                date: entry.date,
                temperature: entry.temperature,
                conditionTag: entry.conditionTag,
                conditionLabel: entry.conditionLabel,
                isDay: entry.isDay,
                phrase: phrase,
                feelsLike: entry.feelsLike,
                high: entry.high,
                low: entry.low,
                precipProbability: entry.precipProbability,
                hourlyPreview: entry.hourlyPreview,
                dailyPreview: entry.dailyPreview,
                locationName: entry.locationName
            )
            completion(snapshotEntry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        Task {
            do {
                let entry = try await fetchWeatherEntry()
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                // Read the phrase the app saved, or generate one as fallback
                let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
                let phrase: String
                if let sharedPhrase = defaults.string(forKey: "currentPhrase"), !sharedPhrase.isEmpty {
                    phrase = sharedPhrase
                } else {
                    phrase = await phraseEngine.selectPhrase(
                        conditionTag: .partlyCloudy,
                        tempF: 72,
                        mode: .clean,
                        isDay: true
                    )
                }
                let fallback = WeatherWidgetEntry(
                    date: Date(),
                    temperature: 72,
                    conditionTag: .partlyCloudy,
                    conditionLabel: "Partly Cloudy",
                    isDay: true,
                    phrase: phrase,
                    feelsLike: 70,
                    high: 78,
                    low: 62,
                    precipProbability: 0,
                    hourlyPreview: WeatherWidgetEntry.placeholder.hourlyPreview,
                    dailyPreview: WeatherWidgetEntry.placeholder.dailyPreview,
                    locationName: "The Damn Weather"
                )
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
                let timeline = Timeline(entries: [fallback], policy: .after(nextUpdate))
                completion(timeline)
            }
        }
    }

    private func fetchWeatherEntry() async throws -> WeatherWidgetEntry {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
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

        // Use the phrase the app shared, or generate a fresh one
        let phrase: String
        if let sharedPhrase = defaults.string(forKey: "currentPhrase"), !sharedPhrase.isEmpty {
            phrase = sharedPhrase
        } else {
            let modeStr = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
            let mode = PhraseMode(rawValue: modeStr) ?? .clean
            phrase = await phraseEngine.selectPhrase(
                conditionTag: conditionTag,
                tempF: tempF,
                mode: mode,
                isDay: current.isDaylight
            )
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
