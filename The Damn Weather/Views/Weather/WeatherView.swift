import SwiftUI
import WeatherKit
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
    var attribution: WeatherAttribution? = nil

    @State private var scrollOffset: CGFloat = 0

    /// Hours from the current hour onward — precomputed to stabilize the view tree.
    private var currentAndFutureHours: [HourlyForecastPoint] {
        let hourStart = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return weather.hourly.filter { $0.time >= hourStart }
    }

    /// How far collapsed the hero is (0 = fully expanded, 1 = fully collapsed).
    /// 350pt window = smooth, gentle collapse across the full hero height.
    private var collapseProgress: CGFloat {
        min(1, max(0, scrollOffset / 350))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spaceLG) {
                // Severe weather alert banner
                if !weather.alerts.isEmpty {
                    SevereAlertBanner(alerts: weather.alerts, timezone: weather.timezone)
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
                    collapseProgress: collapseProgress,
                    airQuality: weather.airQuality,
                    isPartial: weather.isPartial,
                    shareTimezone: weather.timezone,
                    shareAttribution: attribution
                )

                // "Starting soon" callout — only when dry now but precipitation
                // is expected within the hour.
                if let minutes = PrecipitationSoonBanner.minutesUntilStart(weather.minutePrecipitation) {
                    PrecipitationSoonBanner(
                        minutes: minutes,
                        isSnow: [.snow, .heavySnow, .freezingRain].contains(weather.current.conditionTag)
                            || weather.current.temperature <= 34
                    )
                }

                // Minute-by-minute precipitation summary
                if weather.minutePrecipitation.contains(where: { $0.intensity > 0 }) {
                    PrecipitationCard(data: weather.minutePrecipitation)
                }

                // Hourly forecast (filter precomputed to avoid re-running on every body evaluation)
                HourlyForecastView(
                    hours: currentAndFutureHours,
                    timezone: weather.timezone,
                    unit: temperatureUnit
                )

                // Daily forecast
                DailyForecastView(
                    days: weather.daily,
                    timezone: weather.timezone,
                    unit: temperatureUnit
                )

                // Weather details grid — hidden when the snapshot is a
                // cache-hydrated partial (wind, UV, visibility, cloud cover,
                // pressure, humidity, dew point are all 0). Fresh fetch will
                // replace the snapshot and the grid will appear in place.
                if !weather.isPartial {
                    WeatherDetailsGrid(
                        weather: weather,
                        unit: temperatureUnit
                    )
                }

                // Apple Weather attribution
                WeatherAttributionView(attribution: attribution)
                    .padding(.top, DesignTokens.spaceMD)
                    .padding(.bottom, DesignTokens.spaceSM)
            }
            .padding(.horizontal, DesignTokens.spaceMD)
            .frame(maxWidth: DesignTokens.maxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Reserve space for the floating header overlay so content (and
            // the system pull-to-refresh spinner) start below it instead of
            // landing behind the "thedamnweather / Explicit" bar.
            Color.clear.frame(height: topInset)
        }
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
