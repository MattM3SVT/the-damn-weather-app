import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style dew point detail page with comfort zones and 24-hour chart.
struct DewPointDetailView: View {
    let weather: WeatherSnapshot
    let unit: TemperatureUnit

    private var dewPointF: Double { weather.current.dewPoint }

    private var comfortLevel: String {
        switch dewPointF {
        case ..<50: return "Dry & Comfortable"
        case ..<55: return "Comfortable"
        case ..<60: return "Slightly Humid"
        case ..<65: return "Noticeable"
        case ..<70: return "Sticky"
        default: return "Oppressive"
        }
    }

    private var description: String {
        switch dewPointF {
        case ..<50:
            return "The dew point is low, meaning the air is dry and comfortable. Your skin might disagree, but your hair is living its best life."
        case ..<55:
            return "Comfortable dew point. The air has just the right amount of moisture — not too dry, not too swampy. Goldilocks would approve."
        case ..<60:
            return "Dew point is creeping up. You might start to notice a hint of humidity in the air. Nothing dramatic yet."
        case ..<65:
            return "Dew point at \(unit.format(dewPointF)) means the humidity is becoming noticeable. Sweat will start to linger a bit longer."
        case ..<70:
            return "It's getting sticky out there. The dew point is high enough that your body's cooling system is going to start complaining."
        default:
            return "Oppressive humidity. The dew point is at \(unit.format(dewPointF)) — the air is thick, heavy, and deeply unpleasant. Sweating won't help."
        }
    }

    /// Comfort zone boundaries converted to user's unit
    private var comfortZoneLow: Double { unit.convert(50) }
    private var comfortZoneHigh: Double { unit.convert(60) }
    private var stickyZone: Double { unit.convert(65) }

    private var dewPointRange: ClosedRange<Double> {
        let vals = weather.hourly.map { unit.convert($0.dewPoint) }
        let lo = (vals.min() ?? 40) - 3
        let hi = (vals.max() ?? 70) + 3
        return lo...hi
    }

    var body: some View {
        WeatherDetailPage(
            icon: "drop.deferred.fill",
            title: "Dew Point",
            currentValue: unit.format(dewPointF),
            subtitle: comfortLevel,
            description: description,
            accentColor: .blue
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                Chart {
                // Comfortable zone (below ~55°F)
                if dewPointRange.lowerBound < comfortZoneLow {
                    RectangleMark(
                        xStart: .value("Start", weather.hourly.first?.time ?? Date()),
                        xEnd: .value("End", weather.hourly.last?.time ?? Date()),
                        yStart: .value("Low", dewPointRange.lowerBound),
                        yEnd: .value("High", min(comfortZoneLow, dewPointRange.upperBound))
                    )
                    .foregroundStyle(.green.opacity(0.06))
                }

                // Sticky zone (above ~65°F)
                if dewPointRange.upperBound > stickyZone {
                    RectangleMark(
                        xStart: .value("Start", weather.hourly.first?.time ?? Date()),
                        xEnd: .value("End", weather.hourly.last?.time ?? Date()),
                        yStart: .value("Low", max(stickyZone, dewPointRange.lowerBound)),
                        yEnd: .value("High", dewPointRange.upperBound)
                    )
                    .foregroundStyle(.red.opacity(0.06))
                }

                // Area fill
                ForEach(weather.hourly) { hour in
                    AreaMark(
                        x: .value("Time", hour.time),
                        y: .value("Dew Point", unit.convert(hour.dewPoint))
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Dew point line
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Dew Point", unit.convert(hour.dewPoint))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Now indicator
                nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                // Current value dot
                if let current = interpolatedCurrentValueConverted(
                    hourly: weather.hourly,
                    keyPath: \.dewPoint,
                    convert: { unit.convert($0) }
                ) {
                    currentValuePoint(time: current.time, value: current.value, yLabel: "Dew Point", color: .blue)
                }
            }
            .chartYScale(domain: dewPointRange)
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
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(unit.formatShort(v))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            .frame(height: 180)

                // Chart band legend
                HStack(spacing: DesignTokens.spaceSM) {
                    LegendDot(color: .green, label: "Comfortable (<55°)")
                    LegendDot(color: .yellow, label: "Noticeable (55–65°)")
                    LegendDot(color: .orange, label: "Sticky (65–70°)")
                    LegendDot(color: .red, label: "Oppressive (70°+)")
                }
            }
        }
    }
}
