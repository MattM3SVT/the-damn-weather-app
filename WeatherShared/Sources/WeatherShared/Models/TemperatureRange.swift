import Foundation

/// Temperature range categories for phrase matching.
/// Matches the website's getTempRange() from utils.js.
public enum TemperatureRange: String, Codable, CaseIterable, Sendable {
    case extremeCold = "extreme-cold"
    case cold
    case cool
    case mild
    case warm
    case hot
    case extremeHot = "extreme-hot"

    nonisolated public init(fahrenheit: Double) {
        switch fahrenheit {
        case ..<0:
            self = .extremeCold
        case 0...32:
            self = .cold
        case 33...50:
            self = .cool
        case 51...65:
            self = .mild
        case 66...80:
            self = .warm
        case 81...95:
            self = .hot
        default:
            self = .extremeHot
        }
    }

    nonisolated public var label: String {
        switch self {
        case .extremeCold: return "Extreme Cold"
        case .cold: return "Cold"
        case .cool: return "Cool"
        case .mild: return "Mild"
        case .warm: return "Warm"
        case .hot: return "Hot"
        case .extremeHot: return "Extreme Heat"
        }
    }
}
