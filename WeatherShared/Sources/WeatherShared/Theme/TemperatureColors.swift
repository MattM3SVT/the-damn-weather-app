import SwiftUI

/// Temperature-based color mapping for gradients and accents.
/// Ported from main.css lines 133-142.
public enum TemperatureColors {
    /// Accent color based on temperature range
    public static func accent(for range: TemperatureRange) -> Color {
        switch range {
        case .extremeCold, .cold:
            return .accentBlue
        default:
            return .accentRed
        }
    }

    /// Gradient color for temperature bars in daily forecast
    public static func barGradient() -> LinearGradient {
        LinearGradient(
            colors: [.accentBlue, Color(hex: "90be6d"), Color(hex: "f9c74f"), .accentRed],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Temperature color for a specific value
    public static func color(for tempF: Double) -> Color {
        switch tempF {
        case ..<0: return Color(hex: "1d3557")
        case ..<32: return .accentBlue
        case ..<50: return Color(hex: "90be6d")
        case ..<65: return Color(hex: "a8dadc")
        case ..<80: return Color(hex: "f9c74f")
        case ..<95: return Color(hex: "f4845f")
        default: return .accentRed
        }
    }
}
