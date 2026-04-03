import SwiftUI
import WeatherShared

/// Hero section — big temperature, sarcastic phrase, and quick stats.
/// Port of the website's hero section from index.html lines 122-150.
struct HeroSection: View {
    let weather: CurrentWeatherData
    let phrase: String
    let locationName: String
    let currentTime: String
    let unit: TemperatureUnit
    let onRefreshPhrase: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }
    private var iconSize: CGFloat { isRegular ? 140 : DesignTokens.heroIconSize }
    private var tempSize: CGFloat { isRegular ? 128 : DesignTokens.heroTempSize }
    private var phraseSize: CGFloat { isRegular ? 28 : DesignTokens.phraseSize }

    var body: some View {
        VStack(spacing: isRegular ? DesignTokens.spaceLG : DesignTokens.spaceMD) {
            // Weather icon
            WeatherIcon(condition: weather.conditionTag, isDay: weather.isDay, size: iconSize)
                .symbolEffect(.bounce, value: weather.conditionTag)

            // Temperature
            Text(unit.format(weather.temperature))
                .font(.system(size: tempSize, weight: .black, design: .rounded))
                .contentTransition(.numericText())

            // Sarcastic phrase — the star of the show
            PhraseText(phrase: phrase, size: phraseSize, onTap: onRefreshPhrase)

            // Location name + time
            if !locationName.isEmpty {
                HStack(spacing: 6) {
                    Text(locationName)
                    if !currentTime.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(currentTime)
                    }
                }
                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                .foregroundStyle(.secondary)
            }

            // Quick stats row
            HStack(spacing: DesignTokens.spaceLG) {
                StatItem(label: "Feels Like", value: unit.format(weather.feelsLike))
                StatItem(label: "Condition", value: weather.conditionTag.label)
                StatItem(label: "Wind", value: weather.windSpeed.windSpeedString)
                StatItem(label: "UV Index", value: "\(weather.uvIndex)")
            }
            .frame(maxWidth: 500)
            .padding(.top, DesignTokens.spaceSM)
        }
        .padding(.vertical, DesignTokens.spaceXL)
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: DesignTokens.captionSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: DesignTokens.smallSize, weight: .semibold))
        }
    }
}
