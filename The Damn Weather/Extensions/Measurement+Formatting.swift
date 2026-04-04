import Foundation

extension Double {
    /// Wind direction as compass text (N, NE, etc.)
    /// Port of getWindDirection() from utils.js
    var compassDirection: String {
        let dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = ((Int((self / 22.5).rounded()) % 16) + 16) % 16
        return dirs[index]
    }

    /// UV index severity label
    /// Port of getUVLevel() from utils.js
    var uvLevel: String {
        switch self {
        case ...2: return "Low"
        case ...5: return "Moderate"
        case ...7: return "High"
        case ...10: return "Very High"
        default: return "Extreme"
        }
    }

    /// Humidity description
    /// Port of getHumidityDesc() from utils.js
    var humidityDescription: String {
        switch self {
        case ..<30: return "Dry"
        case ..<60: return "Comfortable"
        case ..<80: return "Humid"
        default: return "Very Humid"
        }
    }

    /// Visibility description
    var visibilityDescription: String {
        switch self {
        case ..<1: return "Very Poor"
        case ..<3: return "Poor"
        case ..<6: return "Moderate"
        case ..<10: return "Good"
        default: return "Excellent"
        }
    }

    /// Format as pressure string
    var pressureString: String {
        "\(Int(self.rounded())) hPa"
    }

    /// Format as wind speed
    var windSpeedString: String {
        "\(Int(self.rounded())) mph"
    }

    /// Format as percentage
    var percentString: String {
        "\(Int(self.rounded()))%"
    }

    /// Format as distance in miles
    var milesString: String {
        if self >= 10 {
            return "\(Int(self.rounded())) mi"
        }
        return String(format: "%.1f mi", self)
    }
}
