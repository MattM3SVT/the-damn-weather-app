//
//  The_Damn_WeatherApp.swift
//  The Damn Weather
//
//  Created by Matthew Cosensci on 4/2/26.
//

import SwiftUI
import SwiftData
import WeatherShared

@main
struct The_Damn_WeatherApp: App {
    @State private var appState = AppState()
    @State private var locationService = LocationService()

    let modelContainer: ModelContainer

    init() {
        // Pre-create App Group subdirectories before anything else accesses the container.
        // WidgetKit's internal CoreData tries to use Library/Application Support in the
        // App Group container — if it doesn't exist, CoreData logs verbose sandbox errors
        // (it recovers, but the logs are noisy and indicate a race condition).
        Self.ensureAppGroupDirectories()

        // Create model container — falls back to in-memory store if persistent storage fails
        do {
            modelContainer = try ModelContainer(for: SavedLocation.self)
        } catch {
            // Persistent storage failed (corruption, migration, disk full) — use in-memory so the app still launches
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(for: SavedLocation.self, configurations: config)
            } catch {
                // This should never happen, but if it does, create a bare container
                // rather than crashing the app on launch.
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }
    }

    /// Ensure App Group shared container has required subdirectories.
    /// Called early in init() so WidgetKit's internal CoreData doesn't fail on first access.
    private static func ensureAppGroupDirectories() {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        ) else { return }

        let appSupport = groupURL.appendingPathComponent("Library/Application Support")
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(locationService: locationService, appState: appState)
                .environment(appState)
                .modelContainer(modelContainer)
                .background(Color.black)
        }
    }
}
