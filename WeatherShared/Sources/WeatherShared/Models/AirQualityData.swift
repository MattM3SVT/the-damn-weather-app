import Foundation
import SwiftUI

/// Top-level air quality payload attached to `WeatherSnapshot`. Optional: nil
/// when AirNow has no data for this lat/lon, when the API key is missing or
/// invalid, or when the fetch fails silently. Callers treat nil as "hide the
/// card".
public struct AirQualityData: Sendable, Codable {
    public let aqi: Int
    public let category: AirQualityCategory
    public let primaryPollutant: Pollutant
    public let pollutants: [PollutantReading]
    public let observedAt: Date
    public let reportingArea: String?
    /// Yesterday's peak AQI at this location (max across all pollutants for
    /// the day). AirNow's free historical endpoint is a daily aggregate, not
    /// hourly, so this is the best yesterday-comparison signal we can build.
    /// Nil when yesterday's fetch failed or returned no rows.
    public let yesterdayPeakAQI: Int?

    public init(
        aqi: Int,
        category: AirQualityCategory,
        primaryPollutant: Pollutant,
        pollutants: [PollutantReading],
        observedAt: Date,
        reportingArea: String?,
        yesterdayPeakAQI: Int?
    ) {
        self.aqi = aqi
        self.category = category
        self.primaryPollutant = primaryPollutant
        self.pollutants = pollutants
        self.observedAt = observedAt
        self.reportingArea = reportingArea
        self.yesterdayPeakAQI = yesterdayPeakAQI
    }
}

/// One pollutant's AQI reading. AirNow's free CSV endpoint returns AQI per
/// pollutant but not raw concentrations, so this model holds only the AQI
/// value. If we add a provider that reports concentrations later, we'd
/// extend this struct.
public struct PollutantReading: Sendable, Codable, Identifiable, Hashable {
    public var id: String { pollutant.rawValue }
    public let pollutant: Pollutant
    public let aqi: Int

    public init(pollutant: Pollutant, aqi: Int) {
        self.pollutant = pollutant
        self.aqi = aqi
    }
}

/// Supported pollutants. Order of cases is the order we display in the
/// pollutant table (gases first, particulates last, mirroring Apple Weather).
/// AirNow's `ParameterName` strings are mapped via `Pollutant.init(airNowName:)`.
public enum Pollutant: String, Sendable, Codable, CaseIterable {
    case co, no2, o3, so2, pm10, pm25

    public init?(airNowName: String) {
        switch airNowName.uppercased() {
        case "CO":          self = .co
        case "NO2":         self = .no2
        case "O3", "OZONE": self = .o3
        case "SO2":         self = .so2
        case "PM10":        self = .pm10
        case "PM2.5", "PM25": self = .pm25
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .co:   return "Carbon Monoxide"
        case .no2:  return "Nitrogen Dioxide"
        case .o3:   return "Ozone"
        case .so2:  return "Sulfur Dioxide"
        case .pm10: return "Particulates Under 10μm"
        case .pm25: return "Particulates Under 2.5μm"
        }
    }

    /// Short subscript-styled symbol for the pollutant row's leading label.
    public var shortSymbol: String {
        switch self {
        case .co:   return "CO"
        case .no2:  return "NO₂"
        case .o3:   return "O₃"
        case .so2:  return "SO₂"
        case .pm10: return "PM₁₀"
        case .pm25: return "PM₂․₅"
        }
    }

    /// Natural-language explanation shown in the "Primary Pollutant" card. Text
    /// follows Apple Weather's style, no em dashes (per project copy rules).
    public var contextExplanation: String {
        switch self {
        case .co:
            return "Carbon monoxide is an odorless gas produced by car exhaust, stoves, and incomplete combustion. Levels rise in heavy traffic and poorly ventilated spaces."
        case .no2:
            return "Nitrogen dioxide comes from burning fuel in cars, trucks, and power plants. It's typically highest near busy roads and during rush hour."
        case .o3:
            return "Ozone is typically elevated due to traffic, fossil fuel combustion, and fires, and can be transported far distances."
        case .so2:
            return "Sulfur dioxide comes from burning fossil fuels, especially coal and oil, and from industrial processes. It can irritate the airways."
        case .pm10:
            return "Coarse particulates include dust, pollen, and mold. Windblown dust, unpaved roads, construction, and agricultural activity all contribute."
        case .pm25:
            return "Fine particulates come from vehicle exhaust, wildfires, power plants, and wood-burning stoves. They're small enough to reach deep into the lungs."
        }
    }
}

/// Six-level US EPA AQI category. `from(aqi:)` computes the category from a
/// raw AQI value using standard EPA breakpoints.
public enum AirQualityCategory: Int, Sendable, Codable, CaseIterable {
    case good = 1
    case moderate = 2
    case unhealthyForSensitive = 3
    case unhealthy = 4
    case veryUnhealthy = 5
    case hazardous = 6

    public static func from(aqi: Int) -> AirQualityCategory {
        switch aqi {
        case ..<51:    return .good
        case ..<101:   return .moderate
        case ..<151:   return .unhealthyForSensitive
        case ..<201:   return .unhealthy
        case ..<301:   return .veryUnhealthy
        default:       return .hazardous
        }
    }

    public var label: String {
        switch self {
        case .good:                  return "Good"
        case .moderate:              return "Moderate"
        case .unhealthyForSensitive: return "Unhealthy for Sensitive Groups"
        case .unhealthy:             return "Unhealthy"
        case .veryUnhealthy:         return "Very Unhealthy"
        case .hazardous:             return "Hazardous"
        }
    }

    /// EPA-authored health guidance, paraphrased to match the app's voice. No
    /// em dashes (per project copy rules).
    public var healthInfo: String {
        switch self {
        case .good:
            return "Air quality is satisfactory and poses little or no health risk."
        case .moderate:
            return "Air quality is acceptable. Unusually sensitive people may want to limit long stretches of strenuous activity outside."
        case .unhealthyForSensitive:
            return "Members of sensitive groups, including kids, older adults, and people with heart or lung conditions, may experience health effects. The general public is less likely to be affected."
        case .unhealthy:
            return "Some members of the general public may experience health effects. Sensitive groups may experience more serious effects. Consider shortening outdoor workouts."
        case .veryUnhealthy:
            return "Health alert. The risk of health effects is increased for everyone. Avoid strenuous outdoor activity and keep windows closed."
        case .hazardous:
            return "Health warning of emergency conditions. Everyone is more likely to be affected. Stay indoors and keep activity levels low."
        }
    }

    /// Primary accent color used for the hero icon and gauge range around the
    /// dot. Matches the dominant stop of the rainbow gradient for this band so
    /// the color read stays consistent between the gauge and the rest of the
    /// sheet.
    public var accentColor: Color {
        switch self {
        case .good:                  return .green
        case .moderate:              return .yellow
        case .unhealthyForSensitive: return .orange
        case .unhealthy:             return .red
        case .veryUnhealthy:         return .purple
        case .hazardous:             return Color(red: 0.5, green: 0.0, blue: 0.12) // maroon
        }
    }

    /// SF Symbol variant that matches severity. Apple's `aqi.low` reads as a
    /// small concentric arc, `aqi.medium` is fuller, `aqi.high` is fullest.
    public var sfSymbol: String {
        switch self {
        case .good, .moderate:                   return "aqi.low"
        case .unhealthyForSensitive, .unhealthy: return "aqi.medium"
        case .veryUnhealthy, .hazardous:         return "aqi.high"
        }
    }
}
