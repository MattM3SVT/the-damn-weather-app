import SwiftUI

/// Dynamic background gradients based on weather condition, day/night, and color scheme.
/// Ported from main.css lines 61-131.
public enum WeatherGradients {
    public static func gradient(
        for condition: WeatherConditionTag,
        isDay: Bool,
        colorScheme: ColorScheme
    ) -> LinearGradient {
        let colors = stops(for: condition, isDay: isDay, colorScheme: colorScheme)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func stops(
        for condition: WeatherConditionTag,
        isDay: Bool,
        colorScheme: ColorScheme
    ) -> [Color] {
        let isDark = colorScheme == .dark

        switch condition {
        case .clear:
            if isDay {
                return isDark
                    ? [Color(hex: "0c1445"), Color(hex: "1a1d3a"), Color(hex: "0f1117")]
                    : [Color(hex: "87ceeb"), Color(hex: "e0f0ff"), Color(hex: "f8f9fa")]
            } else {
                return isDark
                    ? [Color(hex: "0c1445"), Color(hex: "1a1d3a"), Color(hex: "0f1117")]
                    : [Color(hex: "2c3e6b"), Color(hex: "4a5a8a"), Color(hex: "c8cfe0")]
            }

        case .partlyCloudy, .cloudy:
            return isDark
                ? [Color(hex: "1a1d27"), Color(hex: "252836"), Color(hex: "0f1117")]
                : [Color(hex: "c8d6e5"), Color(hex: "dfe6e9"), Color(hex: "f8f9fa")]

        case .rain, .heavyRain, .drizzle:
            return isDark
                ? [Color(hex: "0a0e14"), Color(hex: "1a1d27"), Color(hex: "0f1117")]
                : [Color(hex: "636e72"), Color(hex: "b2bec3"), Color(hex: "dfe6e9")]

        case .snow, .heavySnow:
            return isDark
                ? [Color(hex: "1a2030"), Color(hex: "252d3f"), Color(hex: "0f1117")]
                : [Color(hex: "dce6f1"), Color(hex: "ecf0f5"), Color(hex: "f8f9fa")]

        case .thunderstorm:
            return isDark
                ? [Color(hex: "05080d"), Color(hex: "111520"), Color(hex: "0f1117")]
                : [Color(hex: "2d3436"), Color(hex: "636e72"), Color(hex: "b2bec3")]

        case .fog:
            return isDark
                ? [Color(hex: "15181f"), Color(hex: "1e2230"), Color(hex: "0f1117")]
                : [Color(hex: "d5dbe0"), Color(hex: "e8ecef"), Color(hex: "f8f9fa")]

        case .freezingRain:
            return isDark
                ? [Color(hex: "10141d"), Color(hex: "1a2030"), Color(hex: "0f1117")]
                : [Color(hex: "a4b6c4"), Color(hex: "c5d3de"), Color(hex: "e8edf2")]

        case .wind:
            return isDark
                ? [Color(hex: "151820"), Color(hex: "1e2230"), Color(hex: "0f1117")]
                : [Color(hex: "b8c6d4"), Color(hex: "d4dce4"), Color(hex: "f0f2f5")]

        case .any:
            return isDark
                ? [Color(hex: "0f1117"), Color(hex: "1a1d27"), Color(hex: "0f1117")]
                : [Color(hex: "a8dadc"), Color(hex: "f1faee"), Color(hex: "f8f9fa")]
        }
    }
}
