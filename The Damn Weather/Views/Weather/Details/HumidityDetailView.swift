import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style humidity detail page with 24-hour chart.
struct HumidityDetailView: View {
    let weather: WeatherSnapshot
    let unit: TemperatureUnit

    private var description: String {
        let humidity = weather.current.humidity
        let dewPoint = weather.current.dewPoint
        if humidity < 30 {
            return "Very dry air right now. Your skin hates this. Dew point is \(unit.format(dewPoint)), which means basically no moisture."
        } else if humidity <= 60 {
            return "Comfortable humidity levels. Dew point at \(unit.format(dewPoint)) — this is as pleasant as it gets."
        } else if humidity <= 80 {
            return "Getting humid. Dew point is \(unit.format(dewPoint)) — you'll start to feel that sticky quality in the air."
        } else {
            return "Very humid right now (\(Int(humidity))%). Dew point at \(unit.format(dewPoint)). The air is basically soup."
        }
    }

    var body: some View {
        WeatherDetailPage(
            icon: "humidity.fill",
            title: "Humidity",
            currentValue: weather.current.humidity.percentString,
            subtitle: "Dew point \(unit.format(weather.current.dewPoint))",
            description: description,
            accentColor: .teal
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                Chart {
                // Comfortable zone annotation
                RectangleMark(
                    yStart: .value("Low", 30),
                    yEnd: .value("High", 60)
                )
                .foregroundStyle(.green.opacity(0.08))

                // Area fill under humidity line
                ForEach(weather.hourly) { hour in
                    AreaMark(
                        x: .value("Time", hour.time),
                        y: .value("Humidity", hour.humidity)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.teal.opacity(0.3), .teal.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Humidity line
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Humidity", hour.humidity)
                    )
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Now indicator
                nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                // Current value dot
                if let current = interpolatedCurrentValue(hourly: weather.hourly, keyPath: \.humidity) {
                    currentValuePoint(time: current.time, value: current.value, yLabel: "Humidity", color: .teal)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.hourLabel(timezone: weather.timezone))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            // Y-domain extends to 110 to create visual headroom above 100%.
            // Keeps a line peaking at 100% from riding the plot's top edge
            // and crowding the "Now" pill.
            .chartYScale(domain: 0...110)
            .frame(height: 180)

                // Chart band legend
                HStack(spacing: DesignTokens.spaceMD) {
                    LegendDot(color: .green, label: "Comfortable (30–60%)")
                    LegendDot(color: .yellow, label: "Humid (60–80%)")
                    LegendDot(color: .red, label: "Very Humid (80%+)")
                }
            }
        }
    }
}
