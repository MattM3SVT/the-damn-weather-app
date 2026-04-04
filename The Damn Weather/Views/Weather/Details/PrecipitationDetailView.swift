import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style precipitation detail page with minute, hourly, and daily views.
struct PrecipitationDetailView: View {
    let weather: WeatherSnapshot
    let unit: TemperatureUnit
    @Environment(AppState.self) private var appState

    private var currentPrecip: String {
        appState.precipitationUnit.formatRate(weather.current.precipitation)
    }

    private var todayTotal: String {
        if let today = weather.daily.first {
            return appState.precipitationUnit.format(today.precipitationSum)
        }
        return appState.precipitationUnit.format(0)
    }

    private var description: String {
        let chance = weather.daily.first?.precipitationProbability ?? 0
        let hasMinutePrecip = weather.minutePrecipitation.contains { $0.intensity > 0 }

        if hasMinutePrecip {
            return "Rain is falling right now. Check the next-hour chart to see when it might let up — or not."
        } else if chance > 70 {
            return "High chance of precipitation today (\(Int(chance))%). Bring an umbrella or accept your fate."
        } else if chance > 40 {
            return "Moderate chance of rain today (\(Int(chance))%). It's a coin flip — the weather doesn't care about your plans."
        } else if chance > 10 {
            return "Slight chance of precipitation (\(Int(chance))%). Probably fine, but the sky can always surprise you."
        } else {
            return "No significant precipitation expected. It's dry out there — enjoy it while it lasts."
        }
    }

    private func precipBarGradient(for probability: Double) -> LinearGradient {
        let topOpacity = 0.3 + probability / 100 * 0.7
        let bottomOpacity = 0.05 + probability / 100 * 0.35
        return LinearGradient(
            colors: [.blue.opacity(topOpacity), .blue.opacity(bottomOpacity)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        WeatherDetailPage(
            icon: "drop.fill",
            title: "Precipitation",
            currentValue: currentPrecip,
            subtitle: "Today's total: \(todayTotal)",
            description: description,
            accentColor: .blue
        ) {
            // Hourly precipitation probability chart
            Chart {
                ForEach(weather.hourly) { hour in
                    BarMark(
                        x: .value("Time", hour.time),
                        y: .value("Chance", hour.precipitationProbability)
                    )
                    .foregroundStyle(precipBarGradient(for: hour.precipitationProbability))
                }

                // Now indicator
                nowIndicator(hourlyTimes: weather.hourly.map(\.time))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        .foregroundStyle(.secondary)
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            .chartYScale(domain: 0...100)
        } dailyStrip: {
            // Minute-by-minute section if available
            if !weather.minutePrecipitation.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                    Text("Next Hour")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)

                    Chart(weather.minutePrecipitation) { point in
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Intensity", point.intensity)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.blue.opacity(0.5), .blue.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Intensity", point.intensity)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .frame(height: 120)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                            AxisValueLabel(format: .dateTime.minute())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis(.hidden)
                }
                .padding(.bottom, DesignTokens.spaceSM)

                Divider().overlay(Color.white.opacity(0.05))
            }

            // Daily totals
            ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text(day.date.dayLabel(index: index))
                        .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        .frame(width: 60, alignment: .leading)

                    Image(systemName: "drop.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)

                    Text(day.precipitationProbability.percentString)
                        .font(.system(size: DesignTokens.captionSize))
                        .foregroundStyle(.blue)

                    Spacer()

                    Text(appState.precipitationUnit.format(day.precipitationSum))
                        .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                }
                .padding(.vertical, 4)

                if index < weather.daily.count - 1 {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }
}
