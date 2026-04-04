import SwiftUI

/// Main weather screen — scrollable with all weather sections.
struct WeatherView: View {
    let viewModel: WeatherViewModel
    let appState: AppState
    var sidebarOpen: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spaceLG) {
                // Severe weather alert banner
                if let weather = viewModel.weather, !weather.alerts.isEmpty {
                    SevereAlertBanner(alerts: weather.alerts)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Hero section
                if let weather = viewModel.weather {
                    HeroSection(
                        weather: weather.current,
                        phrase: viewModel.currentPhrase,
                        locationName: viewModel.displayName,
                        currentTime: viewModel.currentTime,
                        unit: viewModel.temperatureUnit,
                        onRefreshPhrase: {
                            Task { await viewModel.refreshPhrase() }
                        },
                        phraseTapEnabled: !sidebarOpen
                    )
                }

                // Minute-by-minute precipitation chart
                if let weather = viewModel.weather, weather.minutePrecipitation.contains(where: { $0.intensity > 0 }) {
                    PrecipitationChart(data: weather.minutePrecipitation)
                }

                // Hourly forecast
                if let weather = viewModel.weather {
                    HourlyForecastView(
                        hours: weather.hourly,
                        timezone: weather.timezone,
                        unit: viewModel.temperatureUnit
                    )
                }

                // Daily forecast
                if let weather = viewModel.weather {
                    DailyForecastView(
                        days: weather.daily,
                        unit: viewModel.temperatureUnit
                    )
                }

                // Weather details grid
                if let weather = viewModel.weather {
                    WeatherDetailsGrid(
                        weather: weather,
                        unit: viewModel.temperatureUnit
                    )
                }

                // Apple Weather attribution
                Text("Weather data provided by Apple Weather")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, DesignTokens.spaceMD)
                    .padding(.bottom, DesignTokens.space2XL)
            }
            .padding(.horizontal, DesignTokens.spaceMD)
            .frame(maxWidth: DesignTokens.maxWidth)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}
