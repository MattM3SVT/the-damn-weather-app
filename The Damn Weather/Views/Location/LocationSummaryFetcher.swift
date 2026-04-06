import Foundation
import CoreLocation
import WeatherKit
import WeatherShared

/// Summary data for a location card (used by both SavedLocationsView and LocationSidebar).
struct LocationSummary: Identifiable, Sendable {
    let id: String
    let temperature: String
    let high: String
    let low: String
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let isDay: Bool
    let phrase: String
}

/// Fetches weather summaries for multiple saved locations in parallel.
/// Shared between SavedLocationsView (iPhone) and LocationSidebar (iPad)
/// to avoid duplicating the same WeatherKit + PhraseEngine logic.
enum LocationSummaryFetcher {

    /// Fetch weather summaries for all locations concurrently.
    /// - Parameters:
    ///   - locationInfos: Array of (key, CLLocation) tuples extracted from SavedLocation models.
    ///   - unit: The temperature unit to format values with.
    ///   - phraseMode: The current phrase mode (clean/explicit).
    ///   - phraseEngine: The engine to generate preview phrases.
    /// - Returns: Dictionary mapping location keys to their summaries.
    static func fetchAll(
        locationInfos: [(key: String, location: CLLocation)],
        unit: TemperatureUnit,
        phraseMode: PhraseMode,
        phraseEngine: PhraseEngine
    ) async -> [String: LocationSummary] {
        let service = WeatherKit.WeatherService.shared

        return await withTaskGroup(of: (String, LocationSummary?).self) { group in
            for info in locationInfos {
                let infoKey = info.key
                let infoLocation = info.location
                group.addTask {
                    do {
                        let weather = try await service.weather(
                            for: infoLocation,
                            including: .current, .daily
                        )

                        let current = weather.0
                        let daily = weather.1

                        let windMph = current.wind.speed.converted(to: .milesPerHour).value
                        let conditionTag = WeatherConditionTag.from(current.condition, windSpeed: windMph)
                        let tempF = current.temperature.converted(to: .fahrenheit).value

                        let phrase = await phraseEngine.selectPhrase(
                            conditionTag: conditionTag,
                            tempF: tempF,
                            mode: phraseMode,
                            isDay: current.isDaylight,
                            trackAsSeen: false  // Preview phrases don't pollute dedup
                        )

                        let todayHigh = daily.first.map { $0.highTemperature.converted(to: .fahrenheit).value } ?? 0
                        let todayLow = daily.first.map { $0.lowTemperature.converted(to: .fahrenheit).value } ?? 0

                        let summary = LocationSummary(
                            id: infoKey,
                            temperature: unit.format(tempF),
                            high: unit.format(todayHigh),
                            low: unit.format(todayLow),
                            conditionTag: conditionTag,
                            conditionLabel: current.condition.description,
                            isDay: current.isDaylight,
                            phrase: phrase
                        )

                        return (infoKey, summary)
                    } catch {
                        return (infoKey, nil)
                    }
                }
            }

            var results: [String: LocationSummary] = [:]
            for await (key, summary) in group {
                if let summary {
                    results[key] = summary
                }
            }
            return results
        }
    }
}
