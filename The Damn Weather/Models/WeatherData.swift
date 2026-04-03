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

    /// Sample data for previewing the UI when WeatherKit auth is not yet available.
    nonisolated static func sampleData(location: CLLocation) -> WeatherSnapshot {
        let now = Date()
        let calendar = Calendar.current

        let current = CurrentWeatherData(
            temperature: 68,
            feelsLike: 65,
            humidity: 55,
            isDay: true,
            precipitation: 0,
            conditionTag: .partlyCloudy,
            conditionLabel: "Partly Cloudy",
            pressure: 1013,
            windSpeed: 8,
            windDirection: 225,
            windGusts: 14,
            cloudCover: 40,
            uvIndex: 5,
            visibility: 10,
            dewPoint: 52
        )

        let hourly = (0..<24).map { i in
            let hour = calendar.date(byAdding: .hour, value: i, to: now)!
            let hourOfDay = calendar.component(.hour, from: hour)
            let isDay = hourOfDay >= 6 && hourOfDay < 20
            let baseTemp = 68.0 + Double(i < 6 ? i * 2 : max(0, 12 - i) * 2)
            let tags: [WeatherConditionTag] = [.clear, .partlyCloudy, .cloudy, .partlyCloudy]
            let windSpd = 8 + Double(i % 5)
            return HourlyForecastPoint(
                time: hour,
                temperature: baseTemp,
                feelsLike: baseTemp - 3,
                precipitationProbability: i > 12 ? Double(i * 5) : 0,
                conditionTag: tags[i % tags.count],
                windSpeed: windSpd,
                windDirection: Double((225 + i * 15) % 360),
                windGusts: windSpd + 5,
                isDay: isDay,
                humidity: 55 + Double(i % 20),
                pressure: 1013 + Double(i % 6) - 3,
                visibility: isDay ? 10 : 6,
                uvIndex: isDay ? max(0, 7 - abs(i - 12)) : 0,
                dewPoint: 52 + Double(i % 8),
                cloudCover: 40 + Double(i % 30),
                precipitationAmount: i > 12 ? Double(i - 12) * 0.02 : 0
            )
        }

        let daily = (0..<10).map { i in
            let day = calendar.date(byAdding: .day, value: i, to: now)!
            let sunrise = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: day)!
            let sunset = calendar.date(bySettingHour: 19, minute: 45, second: 0, of: day)!
            let tags: [WeatherConditionTag] = [.partlyCloudy, .clear, .cloudy, .rain, .clear, .partlyCloudy, .drizzle, .clear, .cloudy, .clear]
            return DailyForecastPoint(
                date: day,
                high: 72 + Double(i % 5) * 2,
                low: 54 + Double(i % 3) * 2,
                conditionTag: tags[i],
                conditionLabel: tags[i].rawValue,
                sunrise: sunrise,
                sunset: sunset,
                precipitationSum: i == 3 || i == 6 ? 0.3 : 0,
                precipitationProbability: i == 3 ? 65 : (i == 6 ? 40 : Double(i * 5)),
                windMax: 12 + Double(i * 2),
                uvIndexMax: max(1, 7 - i)
            )
        }

        return WeatherSnapshot(
            current: current,
            hourly: hourly,
            daily: daily,
            minutePrecipitation: [],
            alerts: [],
            moonPhase: MoonPhaseData(phase: .waxingCrescent, illumination: 0.35),
            timezone: .current,
            fetchedAt: now,
            location: location
        )
    }
}
