import Foundation
import WeatherKit

/// Internal condition tags used for phrase matching.
/// Maps WeatherKit's 37 conditions down to 13 tags matching the phrase database.
public enum WeatherConditionTag: String, Codable, CaseIterable, Sendable {
    case clear
    case partlyCloudy = "partly-cloudy"
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain = "heavy-rain"
    case freezingRain = "freezing-rain"
    case snow
    case heavySnow = "heavy-snow"
    case thunderstorm
    case wind
    case any

    /// Map a WeatherKit condition to our internal tag, with wind override.
    /// Wind speeds > 25 mph override clear/partly-cloudy/cloudy to "wind".
    nonisolated public static func from(_ condition: WeatherCondition, windSpeed: Double = 0) -> WeatherConditionTag {
        let base = mapCondition(condition)

        // Wind override: >25 mph overrides calm conditions
        if windSpeed > 25, [.clear, .partlyCloudy, .cloudy].contains(base) {
            return .wind
        }

        return base
    }

    private nonisolated static func mapCondition(_ condition: WeatherCondition) -> WeatherConditionTag {
        switch condition {
        case .clear, .mostlyClear:
            return .clear
        case .partlyCloudy:
            return .partlyCloudy
        case .mostlyCloudy, .cloudy:
            return .cloudy
        case .foggy, .haze, .smoky:
            return .fog
        case .blowingDust, .windy:
            return .wind
        case .breezy:
            return .clear // Will be overridden by wind check if speed > 25
        case .drizzle:
            return .drizzle
        case .rain, .sunShowers:
            return .rain
        case .heavyRain, .hail:
            return .heavyRain
        case .scatteredThunderstorms, .isolatedThunderstorms, .thunderstorms, .strongStorms:
            return .thunderstorm
        case .tropicalStorm, .hurricane:
            return .thunderstorm
        case .frigid, .hot:
            return .clear // Temperature range handles phrase selection
        case .flurries, .sunFlurries, .snow:
            return .snow
        case .sleet, .wintryMix, .freezingRain, .freezingDrizzle:
            return .freezingRain
        case .blizzard, .blowingSnow, .heavySnow:
            return .heavySnow
        @unknown default:
            return .clear
        }
    }

    /// Human-readable label for display
    nonisolated public var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Foggy"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy Rain"
        case .freezingRain: return "Freezing Rain"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .thunderstorm: return "Thunderstorm"
        case .wind: return "Windy"
        case .any: return "Unknown"
        }
    }

    /// SF Symbol name for this condition
    nonisolated public func sfSymbol(isDay: Bool) -> String {
        switch self {
        case .clear:
            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy:
            return "cloud.fill"
        case .fog:
            return "cloud.fog.fill"
        case .drizzle:
            return "cloud.drizzle.fill"
        case .rain:
            return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .heavyRain:
            return "cloud.heavyrain.fill"
        case .freezingRain:
            return "cloud.sleet.fill"
        case .snow:
            return "cloud.snow.fill"
        case .heavySnow:
            return "snowflake"
        case .thunderstorm:
            return "cloud.bolt.rain.fill"
        case .wind:
            return "wind"
        case .any:
            return "cloud.fill"
        }
    }
}
