import Foundation
import CoreLocation
import WeatherShared

/// Normalized current weather data
struct CurrentWeatherData: Sendable {
    let temperature: Double        // Fahrenheit
    let feelsLike: Double          // Fahrenheit
    let humidity: Double           // 0-100
    let isDay: Bool
    let precipitation: Double      // inches
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let pressure: Double           // hPa
    let windSpeed: Double          // mph
    let windDirection: Double      // degrees
    let windGusts: Double          // mph
    let cloudCover: Double         // 0-100
    let uvIndex: Int
    let visibility: Double         // miles
    let dewPoint: Double           // Fahrenheit
}

/// Normalized hourly forecast point
struct HourlyForecastPoint: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let temperature: Double        // Fahrenheit
    let feelsLike: Double          // Fahrenheit
    let precipitationProbability: Double  // 0-100
    let conditionTag: WeatherConditionTag
    let windSpeed: Double          // mph
    let windDirection: Double      // degrees
    let windGusts: Double          // mph
    let isDay: Bool
    let humidity: Double           // 0-100
    let pressure: Double           // hPa
    let visibility: Double         // miles
    let uvIndex: Int
    let dewPoint: Double           // Fahrenheit
    let cloudCover: Double         // 0-100
    let precipitationAmount: Double // inches
}

/// Normalized daily forecast point
struct DailyForecastPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let high: Double               // Fahrenheit
    let low: Double                // Fahrenheit
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let sunrise: Date
    let sunset: Date
    let precipitationSum: Double   // inches
    let precipitationProbability: Double  // 0-100
    let windMax: Double            // mph
    let uvIndexMax: Int
}

/// Normalized minute-by-minute precipitation
struct MinutePrecipitationPoint: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let intensity: Double          // inches/hour
    let probability: Double        // 0-100
}

/// Severe weather alert
struct WeatherAlertData: Identifiable, Sendable {
    let id = UUID()
    let headline: String
    let description: String
    let severity: AlertSeverity
    let source: String
    let expiresAt: Date?

    enum AlertSeverity: String, Sendable {
        case extreme, severe, moderate, minor, unknown
    }
}

/// Moon phase data
struct MoonPhaseData: Sendable {
    let phase: MoonPhaseType
    let illumination: Double       // 0-1

    enum MoonPhaseType: String, Sendable {
        case newMoon = "New Moon"
        case waxingCrescent = "Waxing Crescent"
        case firstQuarter = "First Quarter"
        case waxingGibbous = "Waxing Gibbous"
        case fullMoon = "Full Moon"
        case waningGibbous = "Waning Gibbous"
        case lastQuarter = "Last Quarter"
        case waningCrescent = "Waning Crescent"

        nonisolated var sfSymbol: String {
            switch self {
            case .newMoon: return "moon.fill"
            case .waxingCrescent: return "moon.haze.fill"
            case .firstQuarter: return "moon.circle.fill"
            case .waxingGibbous: return "moon.circle.fill"
            case .fullMoon: return "moon.stars.fill"
            case .waningGibbous: return "moon.circle.fill"
            case .lastQuarter: return "moon.circle.fill"
            case .waningCrescent: return "moon.haze.fill"
            }
        }
    }
}

/// Complete weather data package
struct WeatherSnapshot: @unchecked Sendable {
    let current: CurrentWeatherData
    let hourly: [HourlyForecastPoint]
    let daily: [DailyForecastPoint]
    let minutePrecipitation: [MinutePrecipitationPoint]
    let alerts: [WeatherAlertData]
    let moonPhase: MoonPhaseData?
    let timezone: TimeZone
    let fetchedAt: Date
    let location: CLLocation  // CLLocation is thread-safe but not marked Sendable

    nonisolated var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 15 * 60 // 15 minutes
    }

}
