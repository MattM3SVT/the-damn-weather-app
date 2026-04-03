import SwiftUI
import WeatherShared

/// Full-screen weather-reactive gradient background.
/// Changes based on weather condition, day/night, and color scheme.
/// Matches the website's dynamic background system from main.css.
struct DynamicBackground: View {
    let condition: WeatherConditionTag
    let isDay: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WeatherGradients.gradient(
            for: condition,
            isDay: isDay,
            colorScheme: colorScheme
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: condition)
        .animation(.easeInOut(duration: 1.5), value: isDay)
    }
}
