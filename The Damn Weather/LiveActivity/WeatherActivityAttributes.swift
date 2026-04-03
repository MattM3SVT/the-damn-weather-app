import ActivityKit
import Foundation

struct WeatherActivityAttributes: ActivityAttributes {
    /// Static data that doesn't change during the activity
    let locationName: String

    /// Dynamic data that updates over time
    struct ContentState: Codable, Hashable {
        let temperature: Int
        let conditionSymbol: String
        let conditionLabel: String
        let phrase: String
        let feelsLike: Int
        let precipProbability: Int
        let windSpeed: Int
        let isDay: Bool
        let hourlyTemps: [Int]   // Next 3 hours
        let hourlyHours: [String] // Labels for next 3 hours
    }
}
