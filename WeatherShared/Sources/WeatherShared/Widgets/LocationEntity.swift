import AppIntents
import Foundation

/// A location the user can pin to a widget. The reserved `.myLocation` entity
/// represents "use CLLocationManager at timeline-evaluation time"; all other
/// entities are saved cities mirrored from the app's SwiftData store via
/// `SavedLocationsStore`.
public struct LocationEntity: AppEntity, Codable, Sendable {
    /// Sentinel ID for the "My Location" (follow-GPS) entry. Kept in sync with
    /// `WeatherViewModel.currentLocationKey` in the main app so the same key
    /// identifies the current-device location across all storage layers.
    public static let myLocationID = "__myLocation__"

    public var id: String            // "__myLocation__" or SavedLocation.uuid
    public var name: String          // "My Location" or SavedLocation.displayName
    public var latitude: Double?     // nil for My Location (resolved at runtime)
    public var longitude: Double?

    public init(id: String, name: String, latitude: Double?, longitude: Double?) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isMyLocation: Bool { id == Self.myLocationID }

    public static let myLocation = LocationEntity(
        id: myLocationID, name: "My Location", latitude: nil, longitude: nil
    )

    // MARK: - AppEntity

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Location")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public static let defaultQuery = LocationEntityQuery()
}

/// Populates the widget's Edit-Widget picker. Reads saved cities from the
/// App Group JSON mirror so the widget extension can serve options without
/// needing SwiftData access in its sandbox.
public struct LocationEntityQuery: EntityQuery, Sendable {
    public init() {}

    /// Resolve a set of IDs back to entities. Called by iOS when hydrating a
    /// previously-configured widget. Stale IDs (deleted cities) are dropped;
    /// the widget provider falls back to My Location when that happens.
    public func entities(for identifiers: [String]) async throws -> [LocationEntity] {
        let all = suggestedList()
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    /// List shown in the Edit-Widget picker: My Location first, then every
    /// saved city in the user's app-defined order.
    public func suggestedEntities() async throws -> [LocationEntity] {
        suggestedList()
    }

    public func defaultResult() async -> LocationEntity? { .myLocation }

    private func suggestedList() -> [LocationEntity] {
        [.myLocation] + SavedLocationsStore.load()
    }
}
