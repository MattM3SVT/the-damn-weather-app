import Foundation
import os.log

private let widgetLog = Logger(subsystem: "DamnWeather", category: "WidgetDataStore")

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
        phraseMode = try container.decodeIfPresent(String.self, forKey: .phraseMode) ?? "clean"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.distantPast
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
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) else {
            return nil
        }
        // Ensure the container directory allows widget extension access.
        // Without this, the default file protection can block background reads.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: container.path
        )
        return container.appendingPathComponent(fileName)
    }

    /// Save weather data to the shared container. Called by the main app after every fetch.
    public static func save(_ data: CachedWeatherData) {
        guard let url = fileURL else {
            widgetLog.error("SAVE FAILED: Could not get app group container URL for '\(AppConstants.appGroupID)'")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            // .atomic ensures all-or-nothing writes (no partial/corrupt files).
            // .completeFileProtectionUntilFirstUserAuthentication ensures the widget
            // extension can read this file even from a background context — the default
            // protection (.completeFileProtection) blocks reads when the device is locked,
            // which prevents WidgetKit background refreshes and can also block the first
            // read when a widget is initially added.
            try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            widgetLog.info("SAVE OK: \(url.path) (\(encoded.count) bytes) temp=\(data.temperature) location=\(data.locationName)")
        } catch {
            widgetLog.error("SAVE FAILED: \(error.localizedDescription) at \(url.path)")
        }
    }

    /// Write a neutral seed entry if nothing exists yet. Lets the widget render
    /// something contextual on first install before WeatherKit returns data.
    /// Safe to call every app launch — it's a no-op once real data exists.
    public static func saveSeedIfMissing() {
        guard let url = fileURL else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let seed = CachedWeatherData(
            temperature: 72,
            conditionTag: "clear",
            conditionLabel: "Loading…",
            isDay: true,
            feelsLike: 72,
            high: 78,
            low: 65,
            locationName: "",
            phrase: "The damn weather is loading.",
            phraseMode: "clean",
            updatedAt: Date.distantPast
        )
        save(seed)
        widgetLog.info("Seeded empty widget cache")
    }

    /// Load weather data from the shared container. Called by the widget to get cached data.
    public static func load() -> CachedWeatherData? {
        guard let url = fileURL else {
            widgetLog.error("LOAD FAILED: Could not get app group container URL for '\(AppConstants.appGroupID)'")
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            widgetLog.warning("LOAD: File does not exist at \(url.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(CachedWeatherData.self, from: data)
            widgetLog.info("LOAD OK: \(url.path) temp=\(decoded.temperature) location=\(decoded.locationName) phrase=\(decoded.phrase.prefix(30))")
            return decoded
        } catch {
            widgetLog.error("LOAD FAILED: Decode error: \(error.localizedDescription) at \(url.path)")
            // Log raw file contents for diagnosis
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                widgetLog.error("LOAD FAILED: Raw JSON (first 200 chars): \(raw.prefix(200))")
            }
            return nil
        }
    }

    /// Diagnostic: Check the state of the shared container (call from main app to verify setup).
    public static func diagnose() -> String {
        let groupID = AppConstants.appGroupID
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return "FAIL: containerURL is nil for '\(groupID)'"
        }

        let url = containerURL.appendingPathComponent(fileName)
        let exists = FileManager.default.fileExists(atPath: url.path)

        var result = "Container: \(containerURL.path)\nFile: \(url.path)\nExists: \(exists)"

        if exists {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let size = attrs[.size] as? Int ?? 0
                let modified = attrs[.modificationDate] as? Date
                let protection = attrs[.protectionKey] as? FileProtectionType
                result += "\nSize: \(size) bytes"
                result += "\nModified: \(modified?.description ?? "unknown")"
                result += "\nProtection: \(protection?.rawValue ?? "not set")"
            }
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                result += "\nDecode: OK — temp=\(decoded.temperature) location=\(decoded.locationName)"
            } else if let data = try? Data(contentsOf: url) {
                result += "\nDecode: FAILED — raw size \(data.count) bytes"
                if let raw = String(data: data, encoding: .utf8) {
                    result += "\nRaw (first 200): \(String(raw.prefix(200)))"
                }
            } else {
                result += "\nRead: FAILED — could not read file data"
            }
        }

        return result
    }

}
