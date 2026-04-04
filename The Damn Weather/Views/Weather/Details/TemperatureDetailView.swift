import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style temperature detail page with 24-hour curve and daily high/low.
struct TemperatureDetailView: View {
    let weather: WeatherSnapshot
    let unit: TemperatureUnit

    private var currentTemp: String {
        unit.format(weather.current.temperature)
    }

    private var feelsLike: String {
        unit.format(weather.current.feelsLike)
    }

    private var description: String {
        let diff = weather.current.temperature - weather.current.feelsLike
        if abs(diff) < 3 {
            return "It feels about the same as the actual temperature right now. Enjoy it while it lasts."
        } else if diff > 0 {
            return "It actually feels cooler than \(currentTemp) right now (\(feelsLike)). Wind chill or humidity is working in your favor for once."
        } else {
            return "It feels warmer than \(currentTemp) right now (\(feelsLike)). Humidity is making things extra fun out there."
        }
    }

    private var tempRange: ClosedRange<Double> {
        let temps = weather.hourly.map { unit.rawValue(from: $0.temperature) }
        let feels = weather.hourly.map { unit.rawValue(from: $0.feelsLike) }
        let allVals = temps + feels
        let lo = (allVals.min() ?? 0) - 5
        let hi = (allVals.max() ?? 100) + 5
        return lo...hi
    }

    var body: some View {
        WeatherDetailPage(
            icon: "thermometer.medium",
            title: "Temperature",
            currentValue: currentTemp,
            subtitle: "Feels like \(feelsLike)",
            description: description,
            accentColor: .orange
        ) {
            VStack(spacing: 8) {
                Chart {
                    // Area fill under actual temperature
                    ForEach(weather.hourly) { hour in
                        AreaMark(
                            x: .value("Time", hour.time),
                            y: .value("Temp", unit.rawValue(from: hour.temperature))
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.orange.opacity(0.3), .orange.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    // Actual temperature line
                    ForEach(weather.hourly) { hour in
                        LineMark(
                            x: .value("Time", hour.time),
                            y: .value("Temp", unit.rawValue(from: hour.temperature)),
                            series: .value("Series", "Actual")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    // Feels like line
                    ForEach(weather.hourly) { hour in
                        LineMark(
                            x: .value("Time", hour.time),
                            y: .value("Temp", unit.rawValue(from: hour.feelsLike)),
                            series: .value("Series", "Feels Like")
                        )
                        .foregroundStyle(.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .interpolationMethod(.catmullRom)
                    }

                    // Now indicator
                    nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                    // Current value dot
                    if let current = interpolatedCurrentValueConverted(
                        hourly: weather.hourly,
                        keyPath: \.temperature,
                        convert: { unit.rawValue(from: $0) }
                    ) {
                        currentValuePoint(time: current.time, value: current.value, yLabel: "Temp", color: .orange)
                    }
                }
                .chartYScale(domain: tempRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                            .foregroundStyle(.secondary)
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v.rounded()))°")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    }
                }

                ChartLegend(items: [
                    (color: .orange, label: "Temperature", dashed: false),
                    (color: .white.opacity(0.35), label: "Feels Like", dashed: true)
                ])
            }
        } dailyStrip: {
            let overallLow = weather.daily.map(\.low).min() ?? 0
            let overallHigh = weather.daily.map(\.high).max() ?? 100

            VStack(spacing: 0) {
                ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                    HStack {
                        Text(day.date.dayLabel(index: index))
                            .font(.system(size: DesignTokens.smallSize, weight: .medium))
                            .frame(width: 60, alignment: .leading)

                        Spacer()

                        Text(unit.format(day.low))
                            .font(.system(size: DesignTokens.captionSize))
                            .foregroundStyle(.secondary)

                        DailyTempBar(
                            low: day.low,
                            high: day.high,
                            overallLow: overallLow,
                            overallHigh: overallHigh
                        )
                        .frame(width: 100)

                        Text(unit.format(day.high))
                            .font(.system(size: DesignTokens.captionSize, weight: .semibold))
                    }
                    .padding(.vertical, 6)

                    if index < weather.daily.count - 1 {
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }
}

/// Compact temperature bar for detail page daily strip
struct DailyTempBar: View {
    let low: Double
    let high: Double
    let overallLow: Double
    let overallHigh: Double

    var body: some View {
        GeometryReader { geo in
            let range = overallHigh - overallLow
            let start = range > 0 ? (low - overallLow) / range : 0
            let end = range > 0 ? (high - overallLow) / range : 1

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.1))
                    .frame(height: 4)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .green, .yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(4, geo.size.width * (end - start)),
                        height: 4
                    )
                    .offset(x: geo.size.width * start)
            }
        }
        .frame(height: 4)
    }
}
