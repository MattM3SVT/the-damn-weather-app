import SwiftUI
import WeatherShared

/// Main weather screen — scrollable with all weather sections.
/// Tracks scroll offset to drive the collapsing hero animation.
struct WeatherView: View {
    let weather: WeatherSnapshot
    let phrase: String
    let locationName: String
    let currentTime: String
    let temperatureUnit: TemperatureUnit
    let appState: AppState
    var sidebarOpen: Bool = false
    var onCollapseProgressChanged: ((CGFloat) -> Void)? = nil
    var onRefreshPhrase: (() -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil

    /// Extra top padding to push content below the floating header overlay
    var topInset: CGFloat = 0

    @State private var scrollOffset: CGFloat = 0

    /// How far collapsed the hero is (0 = fully expanded, 1 = fully collapsed).
    /// 350pt window = smooth, gentle collapse across the full hero height.
    private var collapseProgress: CGFloat {
        min(1, max(0, scrollOffset / 350))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spaceLG) {
                // Top spacer accounts for the floating header overlay
                if topInset > 0 {
                    Color.clear.frame(height: topInset)
                }

                // Severe weather alert banner
                if !weather.alerts.isEmpty {
                    SevereAlertBanner(alerts: weather.alerts)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Hero section — visual-only collapse (no layout changes)
                HeroSection(
                    weather: weather.current,
                    phrase: phrase,
                    locationName: locationName,
                    currentTime: currentTime,
                    unit: temperatureUnit,
                    onRefreshPhrase: {
                        onRefreshPhrase?()
                    },
                    phraseTapEnabled: !sidebarOpen,
                    collapseProgress: collapseProgress
                )

                // Minute-by-minute precipitation summary
                if weather.minutePrecipitation.contains(where: { $0.intensity > 0 }) {
                    PrecipitationCard(data: weather.minutePrecipitation)
                }

                // Hourly forecast
                HourlyForecastView(
                    hours: weather.hourly.filter { $0.time >= Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date() },
                    timezone: weather.timezone,
                    unit: temperatureUnit
                )

                // Daily forecast
                DailyForecastView(
                    days: weather.daily,
                    unit: temperatureUnit
                )

                // Weather details grid
                WeatherDetailsGrid(
                    weather: weather,
                    unit: temperatureUnit
                )

                // Apple Weather attribution
                Text("Weather data provided by Apple Weather")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, DesignTokens.spaceMD)
                    .padding(.bottom, DesignTokens.spaceSM)
            }
            .padding(.horizontal, DesignTokens.spaceMD)
            .frame(maxWidth: DesignTokens.maxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom) {
            // Reserve space for the floating bottom bar so content scrolls fully past it
            Color.clear.frame(height: 56)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
            onCollapseProgressChanged?(collapseProgress)
        }
        .refreshable {
            await onRefresh?()
        }
    }
}
