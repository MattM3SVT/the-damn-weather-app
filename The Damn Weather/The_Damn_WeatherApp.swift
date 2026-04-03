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
        // Create model container once upfront — avoids repeated creation in the view modifier
        do {
            modelContainer = try ModelContainer(for: SavedLocation.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(locationService: locationService, appState: appState)
                .environment(appState)
                .modelContainer(modelContainer)
                .background(Color.black)
                .task {
                    // Set up App Group directory in the background
                    if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
                        let groupAppSupport = groupURL.appendingPathComponent("Library/Application Support")
                        if !FileManager.default.fileExists(atPath: groupAppSupport.path) {
                            try? FileManager.default.createDirectory(at: groupAppSupport, withIntermediateDirectories: true)
                        }
                    }
                }
        }
    }
}
