import Foundation
import os.log

private let savedLocationsLog = Logger(subsystem: "DamnWeather", category: "SavedLocationsStore")

/// Mirrors the user's SwiftData-backed saved cities into a JSON file in the
/// App Group container so the widget extension — which can't query SwiftData
/// in the main-app container — can populate its Edit-Widget picker.
///
/// The app writes on every mutation (add / delete / reorder) and on launch.
/// Same App Group + file-protection pattern as `WidgetDataStore`.
public enum SavedLocationsStore {
    private static let fileName = "saved-locations.json"

    private static var fileURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) else {
            return nil
        }
        return container.appendingPathComponent(fileName)
    }

    /// Read the saved-cities list. Returns an empty array on first launch or
    /// any decode failure — the widget picker then shows only "My Location".
    public static func load() -> [LocationEntity] {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([LocationEntity].self, from: data)
        } catch {
            savedLocationsLog.error("load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Overwrite the mirror. Atomic write + unlocked-until-first-auth so the
    /// widget extension can read it from a background context, matching
    /// `WidgetDataStore`'s protection level.
    public static func save(_ entities: [LocationEntity]) {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(entities)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            savedLocationsLog.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
