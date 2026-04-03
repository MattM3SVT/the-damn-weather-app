import SwiftUI
import WeatherShared

/// Horizontal scrolling hourly forecast.
/// Port of the website's hourly section.
struct HourlyForecastView: View {
    let hours: [HourlyForecastPoint]
    let timezone: TimeZone
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spaceMD) {
            Text("Today, Hour by Hour")
                .font(.system(size: DesignTokens.sectionTitleSize, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DesignTokens.spaceSM) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        HourlyCard(hour: hour, timezone: timezone, unit: unit, isNow: index == 0)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .animation(
                                .easeOut(duration: 0.3).delay(Double(index) * 0.03),
                                value: hours.count
                            )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

struct HourlyCard: View {
    let hour: HourlyForecastPoint
    let timezone: TimeZone
    let unit: TemperatureUnit
    let isNow: Bool

    var body: some View {
        VStack(spacing: DesignTokens.spaceSM) {
            // Time label
            Text(isNow ? "Now" : hour.time.hourLabel(timezone: timezone))
                .font(.system(size: DesignTokens.captionSize, weight: isNow ? .bold : .medium))

            // Weather icon
            CompactWeatherIcon(condition: hour.conditionTag, isDay: hour.isDay)
                .frame(height: DesignTokens.hourlyIconSize)

            // Temperature
            Text(unit.format(hour.temperature))
                .font(.system(size: DesignTokens.smallSize, weight: .semibold))

            // Precipitation probability — always reserve space
            HStack(spacing: 2) {
                Circle()
                    .fill(.blue)
                    .frame(width: 4, height: 4)
                Text(hour.precipitationProbability.percentString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .opacity(hour.precipitationProbability > 0 ? 1 : 0)
        }
        .frame(width: 72)
        .padding(.vertical, DesignTokens.spaceMD)
        .background {
            if isNow {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSM)
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSM))
        .overlay(
            isNow ? RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSM)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                ) : nil
        )
    }
}
