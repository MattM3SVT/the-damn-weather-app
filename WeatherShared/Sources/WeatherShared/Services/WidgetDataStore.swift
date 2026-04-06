import Foundation

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
        updatedAt: Date = Date()
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

    /// Debug helper: check if the file exists at the expected path (without attempting to decode).
    public static func debugFileExists() -> Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Debug helper: return raw file contents as string for diagnostics.
    public static func debugRawContents() -> String? {
        guard let url = fileURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Update just the phrase in the existing cached data. Called after phrase refresh.
    public static func updatePhrase(_ phrase: String, mode: String) {
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
            updatedAt: Date()
        )
        save(cached)
    }
}
