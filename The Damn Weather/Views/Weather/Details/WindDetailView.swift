import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style wind detail page with compass, 24-hour chart, and gust info.
struct WindDetailView: View {
    let weather: WeatherSnapshot

    private var description: String {
        let speed = weather.current.windSpeed
        let gusts = weather.current.windGusts
        if speed < 5 {
            return "Calm conditions right now. The air is barely moving — perfect for anyone who hates wind, which is everyone."
        } else if speed < 15 {
            return "A light breeze from the \(weather.current.windDirection.compassDirection). Nothing that'll ruin your day, probably."
        } else if speed < 25 {
            return "Moderate winds at \(speed.windSpeedString) from the \(weather.current.windDirection.compassDirection). Hold onto your hat — literally."
        } else if gusts > 40 {
            return "Strong winds with gusts up to \(gusts.windSpeedString). Maybe don't open that umbrella unless you want to fly."
        } else {
            return "It's pretty damn windy at \(speed.windSpeedString) with gusts to \(gusts.windSpeedString). Outdoor dining is cancelled."
        }
    }

    private var windRange: ClosedRange<Double> {
        let speeds = weather.hourly.map(\.windSpeed)
        let gusts = weather.hourly.map(\.windGusts)
        let allVals = speeds + gusts
        let lo = max(0, (allVals.min() ?? 0) - 3)
        let hi = (allVals.max() ?? 20) + 3
        return lo...hi
    }

    var body: some View {
        WeatherDetailPage(
            icon: "wind",
            title: "Wind",
            currentValue: weather.current.windSpeed.windSpeedString,
            subtitle: "\(weather.current.windDirection.compassDirection) · Gusts \(weather.current.windGusts.windSpeedString)",
            description: description,
            accentColor: .cyan
        ) {
            Chart {
                // Wind speed
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Speed", hour.windSpeed)
                    )
                    .foregroundStyle(.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Gusts
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Gusts", hour.windGusts)
                    )
                    .foregroundStyle(.cyan.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .interpolationMethod(.catmullRom)
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
                            Text("\(Int(v)) mph")
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
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
                        value: day.windMax.windSpeedString,
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
