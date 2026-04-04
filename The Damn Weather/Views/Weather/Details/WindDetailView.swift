import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style wind detail page with compass, 24-hour chart, and gust info.
struct WindDetailView: View {
    let weather: WeatherSnapshot
    @Environment(AppState.self) private var appState

    private var windUnit: WindSpeedUnit { appState.windSpeedUnit }

    private var description: String {
        let speed = weather.current.windSpeed
        let gusts = weather.current.windGusts
        if speed < 5 {
            return "Calm conditions right now. The air is barely moving — perfect for anyone who hates wind, which is everyone."
        } else if speed < 15 {
            return "A light breeze from the \(weather.current.windDirection.compassDirection). Nothing that'll ruin your day, probably."
        } else if speed < 25 {
            return "Moderate winds at \(windUnit.format(speed)) from the \(weather.current.windDirection.compassDirection). Hold onto your hat — literally."
        } else if gusts > 40 {
            return "Strong winds with gusts up to \(windUnit.format(gusts)). Maybe don't open that umbrella unless you want to fly."
        } else {
            return "It's pretty damn windy at \(windUnit.format(speed)) with gusts to \(windUnit.format(gusts)). Outdoor dining is cancelled."
        }
    }

    private var windRange: ClosedRange<Double> {
        let speeds = weather.hourly.map(\.windSpeed)
        let gusts = weather.hourly.map(\.windGusts)
        let allVals = speeds + gusts
        let padding = max(3, (allVals.max() ?? 20) * 0.1)
        let lo = max(0, (allVals.min() ?? 0) - padding)
        let hi = (allVals.max() ?? 20) + padding
        return lo...hi
    }

    var body: some View {
        WeatherDetailPage(
            icon: "wind",
            title: "Wind",
            currentValue: windUnit.format(weather.current.windSpeed),
            subtitle: "\(weather.current.windDirection.compassDirection) · Gusts \(windUnit.format(weather.current.windGusts))",
            description: description,
            accentColor: .cyan
        ) {
            VStack(spacing: 8) {
                Chart {
                    // Area fill under wind speed
                    ForEach(weather.hourly) { hour in
                        AreaMark(
                            x: .value("Time", hour.time),
                            y: .value("Speed", hour.windSpeed)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.cyan.opacity(0.3), .cyan.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    // Wind speed line
                    ForEach(weather.hourly) { hour in
                        LineMark(
                            x: .value("Time", hour.time),
                            y: .value("Speed", hour.windSpeed),
                            series: .value("Series", "Wind Speed")
                        )
                        .foregroundStyle(.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                    }

                    // Gusts line
                    ForEach(weather.hourly) { hour in
                        LineMark(
                            x: .value("Time", hour.time),
                            y: .value("Speed", hour.windGusts),
                            series: .value("Series", "Gusts")
                        )
                        .foregroundStyle(.mint.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .interpolationMethod(.catmullRom)
                    }

                    // Now indicator
                    nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                    // Current value dot
                    if let current = interpolatedCurrentValue(hourly: weather.hourly, keyPath: \.windSpeed) {
                        currentValuePoint(time: current.time, value: current.value, yLabel: "Speed", color: .cyan)
                    }
                }
                .chartYScale(domain: windRange)
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
                                Text(windUnit.format(v))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    }
                }

                ChartLegend(items: [
                    (color: .cyan, label: "Wind Speed", dashed: false),
                    (color: .mint.opacity(0.6), label: "Gusts", dashed: true)
                ])
            }
        } dailyStrip: {
            VStack(spacing: 0) {
                // Compass at top
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 100, height: 100)

                    ForEach(["N", "E", "S", "W"], id: \.self) { dir in
                        Text(dir)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .offset(compassOffset(for: dir, distance: 58))
                    }

                    Image(systemName: "location.north.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.cyan)
                        .rotationEffect(.degrees(weather.current.windDirection))
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .padding(.bottom, DesignTokens.spaceMD)

                Divider().overlay(Color.white.opacity(0.05))

                // Daily wind max
                ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                    DailyStripRow(
                        dayLabel: day.date.dayLabel(index: index),
                        value: windUnit.format(day.windMax),
                        icon: "wind",
                        iconColor: .cyan
                    )
                    .padding(.vertical, 6)

                    if index < weather.daily.count - 1 {
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }

    private func compassOffset(for direction: String, distance: CGFloat) -> CGSize {
        switch direction {
        case "N": return CGSize(width: 0, height: -distance)
        case "S": return CGSize(width: 0, height: distance)
        case "E": return CGSize(width: distance, height: 0)
        case "W": return CGSize(width: -distance, height: 0)
        default: return .zero
        }
    }
}
