import SwiftUI

/// The Damn Weather for Apple Watch. Deliberately small: current conditions,
/// the phrase, and a six-hour strip. The watch fetches its own data (App
/// Groups don't span devices) but reuses WeatherShared's phrase engine,
/// condition mapping, and formatting.
@main
struct DamnWeatherWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchWeatherView()
        }
    }
}
