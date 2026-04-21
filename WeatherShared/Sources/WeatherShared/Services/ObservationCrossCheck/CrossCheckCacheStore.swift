import Foundation
import os.log

private let cacheLog = Logger(subsystem: "DamnWeather", category: "CrossCheckCache")

/// Codable entry type for the observation cache (NWS+METAR consensus + fetch timestamp).
public struct ObservationCacheEntry: Codable, Sendable {
    public let consensus: SkyConsensus
    public let fetchedAt: Date

    public init(consensus: SkyConsensus, fetchedAt: Date) {
        self.consensus = consensus
        self.fetchedAt = fetchedAt
    }
}

/// Codable entry type for the station-resolution cache (lat/lon → ICAO + fetch timestamp).
public struct StationCacheEntry: Codable, Sendable {
    public let icao: String
    public let fetchedAt: Date

    public init(icao: String, fetchedAt: Date) {
        self.icao = icao
        self.fetchedAt = fetchedAt
    }
}

/// Disk-backed cache for `ObservationCrossCheckService`. Persists the three caches
/// to the App Group container so the main app and widget extension share a single
/// view of NWS/METAR results.
///
/// Without this, each widget refresh spawns a fresh in-memory cache and re-hits
/// both APIs for the same station the main app already queried seconds earlier.
public enum CrossCheckCacheStore {
    private static let observationsFile = "cross-check-observations.json"
    private static let stationsFile     = "cross-check-stations.json"
    private static let noCoverageFile   = "cross-check-no-coverage.json"

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
            cacheLog.error("load \(fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T, to fileName: String) {
        guard let url = url(for: fileName) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            // Atomic write + unlocked-until-first-auth protection so the widget
            // extension can still read the cache from a background context,
            // matching WidgetDataStore's protection level.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            cacheLog.error("save \(fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Observation cache

    public static func loadObservations() -> [String: ObservationCacheEntry] {
        load(observationsFile, as: [String: ObservationCacheEntry].self) ?? [:]
    }

    public static func saveObservations(_ dict: [String: ObservationCacheEntry]) {
        save(dict, to: observationsFile)
    }

    // MARK: - Station cache

    public static func loadStations() -> [String: StationCacheEntry] {
        load(stationsFile, as: [String: StationCacheEntry].self) ?? [:]
    }

    public static func saveStations(_ dict: [String: StationCacheEntry]) {
        save(dict, to: stationsFile)
    }

    // MARK: - No-coverage cache

    public static func loadNoCoverage() -> [String: Date] {
        load(noCoverageFile, as: [String: Date].self) ?? [:]
    }

    public static func saveNoCoverage(_ dict: [String: Date]) {
        save(dict, to: noCoverageFile)
    }
}
