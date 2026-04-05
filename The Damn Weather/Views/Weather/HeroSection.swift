import SwiftUI
import WeatherShared

/// Hero section — big temperature, sarcastic phrase, and quick stats.
/// Supports progressive visual collapse as the user scrolls down (Apple Weather style).
/// IMPORTANT: Only uses opacity/scale transforms — never changes layout height.
/// Changing frame heights in a ScrollView creates a feedback loop that causes twitchy scrolling.
struct HeroSection: View {
    let weather: CurrentWeatherData
    let phrase: String
    let locationName: String
    let currentTime: String
    let unit: TemperatureUnit
    let onRefreshPhrase: () -> Void
    var phraseTapEnabled: Bool = true
    var collapseProgress: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppState.self) private var appState

    private var isRegular: Bool { sizeClass == .regular }
    private var iconSize: CGFloat { isRegular ? 168 : DesignTokens.heroIconSize }
    private var tempSize: CGFloat { isRegular ? 128 : DesignTokens.heroTempSize }
    private var phraseSize: CGFloat { isRegular ? 28 : DesignTokens.phraseSize }

    // MARK: - Collapse progress helpers (visual only — no layout changes)

    /// Maps overall collapse progress to a sub-range (0→1 within that range)
    private func subProgress(start: CGFloat, end: CGFloat) -> CGFloat {
        min(1, max(0, (collapseProgress - start) / (end - start)))
    }

    private var iconProgress: CGFloat { subProgress(start: 0.0, end: 0.3) }
    private var tempProgress: CGFloat { subProgress(start: 0.15, end: 0.5) }
    private var phraseProgress: CGFloat { subProgress(start: 0.3, end: 0.65) }
    private var locationProgress: CGFloat { subProgress(start: 0.4, end: 0.7) }
    private var statsProgress: CGFloat { subProgress(start: 0.5, end: 0.8) }

    var body: some View {
        VStack(spacing: isRegular ? DesignTokens.spaceLG : DesignTokens.spaceSM) {
            // Weather icon
            WeatherIcon(condition: weather.conditionTag, isDay: weather.isDay, size: iconSize)
                .symbolEffect(.bounce, value: weather.conditionTag)
                .scaleEffect(1 - iconProgress * 0.5)
                .opacity(1 - iconProgress)

            // Temperature
            Text(unit.format(weather.temperature))
                .font(.system(size: tempSize, weight: .black, design: .rounded))
                .contentTransition(.numericText())
                .scaleEffect(1 - tempProgress * 0.4, anchor: .top)
                .opacity(1 - tempProgress)

            // Sarcastic phrase — the star of the show
            PhraseText(phrase: phrase, size: phraseSize, isEnabled: phraseTapEnabled, onTap: onRefreshPhrase)
                .opacity(1 - phraseProgress)

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
                .opacity(1 - locationProgress)
            }

            // Quick stats row
            HStack(spacing: DesignTokens.spaceMD) {
                StatItem(label: "Feels Like", value: unit.format(weather.feelsLike))
                StatItem(label: "Condition", value: weather.conditionTag.label)
                StatItem(label: "Wind", value: appState.windSpeedUnit.format(weather.windSpeed))
                StatItem(label: "UV Index", value: "\(weather.uvIndex)")
            }
            .frame(maxWidth: 500)
            .padding(.top, DesignTokens.spaceSM)
            .opacity(1 - statsProgress)
        }
        .padding(.vertical, isRegular ? DesignTokens.spaceXL : DesignTokens.spaceLG)
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
                .minimumScaleFactor(0.8)
        }
    }
}
