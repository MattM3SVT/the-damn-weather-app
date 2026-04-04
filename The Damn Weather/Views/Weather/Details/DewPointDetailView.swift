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
            Chart {
                // Comfortable zone (below ~55°F)
                if dewPointRange.lowerBound < comfortZoneLow {
                    RectangleMark(
                        yStart: .value("Low", dewPointRange.lowerBound),
                        yEnd: .value("High", min(comfortZoneLow, dewPointRange.upperBound))
                    )
                    .foregroundStyle(.green.opacity(0.06))
                }

                // Sticky zone (above ~65°F)
                if dewPointRange.upperBound > stickyZone {
                    RectangleMark(
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
                            Text(unit.formatShort(v))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
        } dailyStrip: {
            VStack(spacing: DesignTokens.spaceSM) {
                HStack(spacing: DesignTokens.spaceSM) {
                    // Comfort scale
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("Comfortable (< 55°)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.yellow).frame(width: 8, height: 8)
                            Text("Noticeable (55–65°)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.orange).frame(width: 8, height: 8)
                            Text("Sticky (65–70°)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Oppressive (70°+)")
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
                        Text(unit.format(dewPointF))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }
}
