import SwiftUI

extension Color {
    // MARK: - Light Theme Colors (from main.css)
    public static let weatherBgLight = Color(hex: "f8f9fa")
    public static let weatherSurfaceLight = Color(hex: "ffffff")
    public static let weatherTextLight = Color(hex: "1a1a2e")
    public static let weatherTextSecondaryLight = Color(hex: "6c757d")
    public static let weatherTextMutedLight = Color(hex: "adb5bd")
    public static let weatherBorderLight = Color(hex: "e9ecef")

    // MARK: - Dark Theme Colors (from main.css)
    public static let weatherBgDark = Color(hex: "0f1117")
    public static let weatherSurfaceDark = Color(hex: "1a1d27")
    public static let weatherTextDark = Color(hex: "e8e8ed")
    public static let weatherTextSecondaryDark = Color(hex: "9ca3af")
    public static let weatherTextMutedDark = Color(hex: "6b7280")
    public static let weatherBorderDark = Color(hex: "2a2d3a")

    // MARK: - Accent Colors
    public static let accentRed = Color(hex: "e63946")
    public static let accentRedHover = Color(hex: "d62839")
    public static let accentBlue = Color(hex: "457b9d")

    // MARK: - Temperature-based accent
    public static func temperatureAccent(for range: TemperatureRange) -> Color {
        switch range {
        case .extremeCold, .cold:
            return .accentBlue
        default:
            return .accentRed
        }
    }

    // MARK: - Hex Initializer
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
