import Foundation
import os.log

private let airQualityCacheLog = Logger(subsystem: "DamnWeather", category: "AirQualityCache")

/// Codable entry type for the air-quality observation cache. Wraps the
/// `AirQualityData` payload with its fetch timestamp so TTL is enforced
/// at read time regardless of the file's mtime.
public struct AirQualityCacheEntry: Codable, Sendable {
    public let data: AirQualityData
    public let fetchedAt: Date

    public init(data: AirQualityData, fetchedAt: Date) {
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// Disk-backed cache for `AirQualityService`. Persists to the App Group
/// container so the main app and (in future) the widget extension share one
/// view of the AirNow data. Mirrors `CrossCheckCacheStore` so the on-disk
/// conventions (atomic writes, protection class, LRU eviction) stay
/// consistent across services.
public enum AirQualityCacheStore {
    private static let observationsFile = "air-quality-current.json"
    private static let noCoverageFile   = "air-quality-no-coverage.json"
    private static let areaStatesFile   = "air-quality-area-states.json"

    private static func url(for fileName: String) -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) else {
            return nil
        }
        return container.appendingPathComponent(fileName)
    }

    private static func load<T: Decodable>(_ fileName: String, as type: T.Type) -> T? {
        guard let url = url(for: fileName),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            airQualityCacheLog.error("load \(fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T, to fileName: String) {
        guard let url = url(for: fileName) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            airQualityCacheLog.error("save \(fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Observation cache

    public static func loadObservations() -> [String: AirQualityCacheEntry] {
        load(observationsFile, as: [String: AirQualityCacheEntry].self) ?? [:]
    }

    public static func saveObservations(_ dict: [String: AirQualityCacheEntry]) {
        save(dict, to: observationsFile)
    }

    // MARK: - No-coverage cache

    public static func loadNoCoverage() -> [String: Date] {
        load(noCoverageFile, as: [String: Date].self) ?? [:]
    }

    public static func saveNoCoverage(_ dict: [String: Date]) {
        save(dict, to: noCoverageFile)
    }

    // MARK: - Reporting area -> state cache

    /// Maps an AirNow reporting area name to its USPS state code, which the
    /// daily historical service needs and the current-observation service
    /// stopped returning in June 2026. Learning one costs an extra request, so
    /// it's cached here; the mapping is a property of the area itself and
    /// doesn't expire, so entries are kept without a TTL.
    public static func loadAreaStates() -> [String: String] {
        load(areaStatesFile, as: [String: String].self) ?? [:]
    }

    public static func saveAreaStates(_ dict: [String: String]) {
        save(dict, to: areaStatesFile)
    }
}
