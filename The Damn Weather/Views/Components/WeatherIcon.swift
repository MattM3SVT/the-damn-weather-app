import SwiftUI
import WeatherShared

/// Weather condition icon using SF Symbols with appropriate rendering
struct WeatherIcon: View {
    let condition: WeatherConditionTag
    let isDay: Bool
    var size: CGFloat = DesignTokens.heroIconSize

    var body: some View {
        Image(systemName: condition.sfSymbol(isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .frame(width: size * 1.2, height: size * 1.2)
    }
}

/// Compact weather icon for hourly/daily forecasts
struct CompactWeatherIcon: View {
    let condition: WeatherConditionTag
    let isDay: Bool
    var size: CGFloat = DesignTokens.hourlyIconSize

    var body: some View {
        Image(systemName: condition.sfSymbol(isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
    }
}
