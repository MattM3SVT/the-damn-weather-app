import SwiftUI
import WeatherShared

/// Detail page types that can be opened from cards
enum WeatherDetailType: Identifiable {
    case temperature, wind, uvIndex, pressure, sun, precipitation
    case visibility, dewPoint, cloudCover, moon, humidity

    var id: String { String(describing: self) }
}

/// Weather details grid — 2-column layout of tappable detail cards.
/// Tap any card to open its Apple Weather-style detail page.
struct WeatherDetailsGrid: View {
    let weather: WeatherSnapshot
    let unit: TemperatureUnit

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppState.self) private var appState
    @State private var selectedDetail: WeatherDetailType?

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: DesignTokens.spaceSM), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spaceMD) {
            Text("The Details")
                .font(.system(size: DesignTokens.sectionTitleSize, weight: .semibold))

            LazyVGrid(columns: columns, spacing: DesignTokens.spaceSM) {
                // Humidity
                DetailCard(
                    icon: "humidity.fill",
                    label: "Humidity",
                    value: weather.current.humidity.percentString,
                    extra: weather.current.humidity.humidityDescription,
                    tappable: true
                )
                .onTapGesture { selectedDetail = .humidity }

                // Wind
                DetailCard(
                    icon: "wind",
                    label: "Wind",
                    value: appState.windSpeedUnit.format(weather.current.windSpeed),
                    extra: "\(weather.current.windDirection.compassDirection) · Gusts \(appState.windSpeedUnit.format(weather.current.windGusts))",
                    tappable: true
                )
                .onTapGesture { selectedDetail = .wind }

                // UV Index
                DetailCard(
                    icon: "sun.max.fill",
                    label: "UV Index",
                    value: "\(weather.current.uvIndex)",
                    extra: Double(weather.current.uvIndex).uvLevel,
                    tappable: true
                )
                .onTapGesture { selectedDetail = .uvIndex }

                // Pressure
                DetailCard(
                    icon: "gauge.medium",
                    label: "Pressure",
                    value: appState.pressureUnit.format(weather.current.pressure),
                    extra: nil,
                    tappable: true
                )
                .onTapGesture { selectedDetail = .pressure }

                // Sunrise/Sunset
                if let today = weather.daily.first {
                    DetailCard(
                        icon: "sunrise.fill",
                        label: "Sun",
                        value: "↑ \(today.sunrise.timeString(timezone: weather.timezone))",
                        extra: "↓ \(today.sunset.timeString(timezone: weather.timezone))",
                        tappable: true
                    )
                    .onTapGesture { selectedDetail = .sun }
                }

                // Precipitation
                if let today = weather.daily.first {
                    DetailCard(
                        icon: "drop.fill",
                        label: "Precipitation",
                        value: appState.precipitationUnit.format(today.precipitationSum),
                        extra: "\(today.precipitationProbability.percentString) chance",
                        tappable: true
                    )
                    .onTapGesture { selectedDetail = .precipitation }
                }

                // Visibility
                DetailCard(
                    icon: "eye.fill",
                    label: "Visibility",
                    value: appState.distanceUnit.format(weather.current.visibility),
                    extra: weather.current.visibility.visibilityDescription,
                    tappable: true
                )
                .onTapGesture { selectedDetail = .visibility }

                // Dew Point
                DetailCard(
                    icon: "drop.deferred.fill",
                    label: "Dew Point",
                    value: unit.format(weather.current.dewPoint),
                    extra: nil,
                    tappable: true
                )
                .onTapGesture { selectedDetail = .dewPoint }

                // Cloud Cover
                DetailCard(
                    icon: "cloud.fill",
                    label: "Cloud Cover",
                    value: weather.current.cloudCover.percentString,
                    extra: nil,
                    tappable: true
                )
                .onTapGesture { selectedDetail = .cloudCover }

                // Temperature (feels like)
                DetailCard(
                    icon: "thermometer.medium",
                    label: "Temperature",
                    value: unit.format(weather.current.temperature),
                    extra: "Feels like \(unit.format(weather.current.feelsLike))",
                    tappable: true
                )
                .onTapGesture { selectedDetail = .temperature }

                // Moon Phase
                if let moon = weather.moonPhase {
                    DetailCard(
                        icon: moon.phase.sfSymbol,
                        label: "Moon",
                        value: moon.phase.rawValue,
                        extra: "\(Int(moon.illumination * 100))% illuminated",
                        tappable: true
                    )
                    .onTapGesture { selectedDetail = .moon }
                }
            }
        }
        .sheet(item: $selectedDetail) { detail in
            detailView(for: detail)
        }
    }

    @ViewBuilder
    private func detailView(for detail: WeatherDetailType) -> some View {
        switch detail {
        case .temperature:
            TemperatureDetailView(weather: weather, unit: unit)
        case .wind:
            WindDetailView(weather: weather)
        case .uvIndex:
            UVIndexDetailView(weather: weather)
        case .pressure:
            PressureDetailView(weather: weather)
        case .sun:
            SunDetailView(weather: weather)
        case .precipitation:
            PrecipitationDetailView(weather: weather, unit: unit)
        case .humidity:
            HumidityDetailView(weather: weather, unit: unit)
        case .visibility:
            VisibilityDetailView(weather: weather)
        case .dewPoint:
            DewPointDetailView(weather: weather, unit: unit)
        case .cloudCover:
            CloudCoverDetailView(weather: weather)
        case .moon:
            MoonDetailView(weather: weather)
        }
    }
}

struct DetailCard: View {
    let icon: String
    let label: String
    let value: String
    let extra: String?
    var tappable: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: DesignTokens.detailIconSize))
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)

                    if tappable {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }

                Text(value)
                    .font(.system(size: DesignTokens.bodySize, weight: .semibold))

                if let extra {
                    Text(extra)
                        .font(.system(size: DesignTokens.captionSize))
                        .foregroundStyle(.secondary)
                } else {
                    // Reserve space so all cards in the row are the same height
                    Text(" ")
                        .font(.system(size: DesignTokens.captionSize))
                        .foregroundStyle(.clear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
