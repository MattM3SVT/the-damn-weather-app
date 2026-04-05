import SwiftUI
import WeatherShared

/// Animated weather condition icon for the hero section
struct WeatherIcon: View {
    let condition: WeatherConditionTag
    let isDay: Bool
    var size: CGFloat = DesignTokens.heroIconSize

    var body: some View {
        AnimatedWeatherIcon(condition: condition, isDay: isDay, size: size)
            .frame(width: size)
    }
}

/// Animated weather icon for hourly/daily forecasts
struct CompactWeatherIcon: View {
    let condition: WeatherConditionTag
    let isDay: Bool
    var size: CGFloat = DesignTokens.hourlyIconSize

    var body: some View {
        AnimatedWeatherIcon(condition: condition, isDay: isDay, size: size)
            .frame(width: size * 1.2, height: size * 1.2)
    }
}
