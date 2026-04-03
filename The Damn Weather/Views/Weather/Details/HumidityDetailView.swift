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
            Chart {
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Humidity", hour.humidity)
                    )
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Comfortable zone annotation
                RectangleMark(
                    yStart: .value("Low", 30),
                    yEnd: .value("High", 60)
                )
                .foregroundStyle(.green.opacity(0.08))
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
            VStack(spacing: DesignTokens.spaceSM) {
                HStack(spacing: DesignTokens.spaceSM) {
                    // Humidity comfort scale
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("Comfortable (30-60%)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.yellow).frame(width: 8, height: 8)
                            Text("Humid (60-80%)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Very Humid (80%+)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Current dew point highlight
                    VStack(spacing: 4) {
                        Text("Dew Point")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(unit.format(weather.current.dewPoint))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }
}
