import Foundation

/// Lightweight hourly forecast point for widget display.
public struct CachedHourlyPoint: Codable, Sendable {
    public let hour: String          // "Now", "3 PM"
    public let temp: Int
    public let conditionTag: String  // WeatherConditionTag raw value
    public let isDay: Bool

    public init(hour: String, temp: Int, conditionTag: String, isDay: Bool) {
        self.hour = hour
        self.temp = temp
        self.conditionTag = conditionTag
        self.isDay = isDay
    }
}

/// Lightweight daily forecast point for widget display.
public struct CachedDailyPoint: Codable, Sendable {
    public let day: String           // "Today", "Mon"
    public let high: Int
    public let low: Int
    public let conditionTag: String  // WeatherConditionTag raw value

    public init(day: String, high: Int, low: Int, conditionTag: String) {
        self.day = day
        self.high = high
        self.low = low
        self.conditionTag = conditionTag
    }
}

/// Cached weather data shared between the main app and widget extension via a JSON file
/// in the App Group container. This is more reliable than UserDefaults for cross-process
/// data sharing on iPhone, where UserDefaults sync can be delayed or fail entirely.
public struct CachedWeatherData: Codable {
    public let temperature: Double
    public let conditionTag: String
    public let conditionLabel: String
    public let isDay: Bool
    public let feelsLike: Double
    public let high: Double
    public let low: Double
    public let locationName: String
    public let phrase: String
    public let phraseMode: String
    public let updatedAt: Date

    /// Pre-generated phrases for multi-entry widget timelines.
    /// The widget uses these to show a different phrase every 15 minutes
    /// without needing to run PhraseEngine in the extension process.
    public let additionalPhrases: [String]

    /// Shorter phrase for the small widget (≤70 chars). Falls back to main phrase if nil.
    public let smallPhrase: String?

    /// Hourly forecast preview for large widget (6 points).
    public let hourlyPreview: [CachedHourlyPoint]

    /// Daily forecast preview for large widget (5 points).
    public let dailyPreview: [CachedDailyPoint]

    public init(
        temperature: Double,
        conditionTag: String,
        conditionLabel: String,
        isDay: Bool,
        feelsLike: Double,
        high: Double,
        low: Double,
        locationName: String,
        phrase: String,
        phraseMode: String,
        updatedAt: Date = Date(),
        additionalPhrases: [String] = [],
        smallPhrase: String? = nil,
        hourlyPreview: [CachedHourlyPoint] = [],
        dailyPreview: [CachedDailyPoint] = []
    ) {
        self.temperature = temperature
        self.conditionTag = conditionTag
        self.conditionLabel = conditionLabel
        self.isDay = isDay
        self.feelsLike = feelsLike
        self.high = high
        self.low = low
        self.locationName = locationName
        self.phrase = phrase
        self.phraseMode = phraseMode
        self.updatedAt = updatedAt
        self.additionalPhrases = additionalPhrases
        self.smallPhrase = smallPhrase
        self.hourlyPreview = hourlyPreview
        self.dailyPreview = dailyPreview
    }

    /// All phrases in order: primary phrase first, then additional.
    public var allPhrases: [String] {
        [phrase] + additionalPhrases
    }

    /// Custom decoder to handle backward compatibility — older cached JSON
    /// won't have the additionalPhrases field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try container.decode(Double.self, forKey: .temperature)
        conditionTag = try container.decode(String.self, forKey: .conditionTag)
        conditionLabel = try container.decode(String.self, forKey: .conditionLabel)
        isDay = try container.decode(Bool.self, forKey: .isDay)
        feelsLike = try container.decode(Double.self, forKey: .feelsLike)
        high = try container.decode(Double.self, forKey: .high)
        low = try container.decode(Double.self, forKey: .low)
        locationName = try container.decode(String.self, forKey: .locationName)
        phrase = try container.decode(String.self, forKey: .phrase)
        phraseMode = try container.decode(String.self, forKey: .phraseMode)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        additionalPhrases = try container.decodeIfPresent([String].self, forKey: .additionalPhrases) ?? []
        smallPhrase = try container.decodeIfPresent(String.self, forKey: .smallPhrase)
        hourlyPreview = try container.decodeIfPresent([CachedHourlyPoint].self, forKey: .hourlyPreview) ?? []
        dailyPreview = try container.decodeIfPresent([CachedDailyPoint].self, forKey: .dailyPreview) ?? []
    }
}

/// File-based data store for sharing weather data between app and widget extension.
/// Uses a JSON file in the shared App Group container — immediately visible to both
/// processes with no cross-process sync uncertainty.
public enum WidgetDataStore {
    private static let fileName = "widget-weather.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Save weather data to the shared container. Called by the main app after every fetch.
    public static func save(_ data: CachedWeatherData) {
        guard let url = fileURL else {
            #if DEBUG
            print("⚠️ WidgetDataStore: Could not get app group container URL")
            #endif
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("⚠️ WidgetDataStore: Failed to save: \(error)")
            #endif
        }
    }

    /// Load weather data from the shared container. Called by the widget to get cached data.
    public static func load() -> CachedWeatherData? {
        guard let url = fileURL else {
            #if DEBUG
            print("⚠️ WidgetDataStore: Could not get app group container URL")
            #endif
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CachedWeatherData.self, from: data)
        } catch {
            #if DEBUG
            print("⚠️ WidgetDataStore: Failed to load: \(error)")
            #endif
            return nil
        }
    }

    /// Update just the phrase(s) in the existing cached data. Called after phrase refresh.
    public static func updatePhrase(_ phrase: String, mode: String, additionalPhrases: [String] = [], smallPhrase: String? = nil) {
        guard var cached = load() else { return }
        cached = CachedWeatherData(
            temperature: cached.temperature,
            conditionTag: cached.conditionTag,
            conditionLabel: cached.conditionLabel,
            isDay: cached.isDay,
            feelsLike: cached.feelsLike,
            high: cached.high,
            low: cached.low,
            locationName: cached.locationName,
            phrase: phrase,
            phraseMode: mode,
            updatedAt: Date(),
            additionalPhrases: additionalPhrases,
            smallPhrase: smallPhrase ?? cached.smallPhrase,
            hourlyPreview: cached.hourlyPreview,
            dailyPreview: cached.dailyPreview
        )
        save(cached)
    }
}
