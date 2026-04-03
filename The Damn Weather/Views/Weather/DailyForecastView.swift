import SwiftUI
import WeatherShared

/// 10-day daily forecast with temperature bars.
/// Port of the website's daily section.
struct DailyForecastView: View {
    let days: [DailyForecastPoint]
    let unit: TemperatureUnit

    private var overallLow: Double {
        days.map(\.low).min() ?? 0
    }

    private var overallHigh: Double {
        days.map(\.high).max() ?? 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spaceMD) {
            Text("The Next 10 Days")
                .font(.system(size: DesignTokens.sectionTitleSize, weight: .semibold))

            GlassPanel {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        DailyRow(
                            day: day,
                            index: index,
                            overallLow: overallLow,
                            overallHigh: overallHigh,
                            unit: unit
                        )

                        if index < days.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.05))
                        }
                    }
                }
                .padding(.vertical, DesignTokens.spaceSM)
            }
        }
    }
}

struct DailyRow: View {
    let day: DailyForecastPoint
    let index: Int
    let overallLow: Double
    let overallHigh: Double
    let unit: TemperatureUnit

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var dayWidth: CGFloat { sizeClass == .regular ? 70 : 50 }
    private var precipWidth: CGFloat { sizeClass == .regular ? 50 : 38 }
    private var tempWidth: CGFloat { sizeClass == .regular ? 42 : 32 }

    var body: some View {
        HStack(spacing: DesignTokens.spaceSM) {
            // Day name
            VStack(alignment: .leading, spacing: 0) {
                Text(day.date.dayLabel(index: index))
                    .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                    .frame(width: dayWidth, alignment: .leading)
                Text(day.date.shortDate())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: dayWidth, alignment: .leading)
            }

            // Weather icon — fixed frame so all rows align
            CompactWeatherIcon(
                condition: day.conditionTag,
                isDay: true,
                size: DesignTokens.dailyIconSize
            )
            .frame(width: 28)

            // Precipitation probability — always reserve space
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
                Text(day.precipitationProbability.percentString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .frame(width: precipWidth, alignment: .leading)
            .opacity(day.precipitationProbability > 0 ? 1 : 0)

            // Low temp
            Text(unit.format(day.low))
                .font(.system(size: DesignTokens.captionSize))
                .foregroundStyle(.secondary)
                .frame(width: tempWidth, alignment: .trailing)

            // Temperature bar
            TemperatureBar(
                low: day.low,
                high: day.high,
                overallLow: overallLow,
                overallHigh: overallHigh,
                unit: unit
            )

            // High temp
            Text(unit.format(day.high))
                .font(.system(size: DesignTokens.captionSize, weight: .semibold))
                .frame(width: tempWidth, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.spaceMD)
        .padding(.vertical, DesignTokens.spaceSM)
    }
}
