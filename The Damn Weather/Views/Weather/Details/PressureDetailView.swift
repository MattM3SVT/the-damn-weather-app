import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style pressure detail page with 24-hour trend.
struct PressureDetailView: View {
    let weather: WeatherSnapshot
    @Environment(AppState.self) private var appState

    private var trend: String {
        guard weather.hourly.count >= 3 else { return "Steady" }
        let recent = weather.hourly.prefix(6).map(\.pressure)
        let first = recent.first ?? 0
        let last = recent.last ?? 0
        let diff = last - first
        if diff > 1.5 { return "Rising" }
        if diff < -1.5 { return "Falling" }
        return "Steady"
    }

    private var trendArrow: String {
        switch trend {
        case "Rising": return "↗"
        case "Falling": return "↘"
        default: return "→"
        }
    }

    private var description: String {
        switch trend {
        case "Rising":
            return "Barometric pressure is rising, which usually means improving conditions. Clear skies might be on the way — don't get too excited though."
        case "Falling":
            return "Pressure is dropping, which often signals incoming weather changes. Clouds, rain, or general atmospheric drama could be headed your way."
        default:
            return "Pressure is holding steady at \(appState.pressureUnit.format(weather.current.pressure)). Stable conditions — the atmosphere is taking a day off."
        }
    }

    private var pressureRange: ClosedRange<Double> {
        let vals = weather.hourly.map(\.pressure)
        let lo = (vals.min() ?? 1010) - 3
        let hi = (vals.max() ?? 1016) + 3
        return lo...hi
    }

    var body: some View {
        WeatherDetailPage(
            icon: "gauge.medium",
            title: "Pressure",
            currentValue: appState.pressureUnit.format(weather.current.pressure),
            subtitle: "\(trend) \(trendArrow)",
            description: description,
            accentColor: .indigo
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                Chart {
                // Standard pressure reference line.
                // Annotation lives at top-RIGHT so it doesn't collide with the
                // "Now" pill at top-left.
                RuleMark(y: .value("Standard", 1013.25))
                    .foregroundStyle(.white.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Standard (1013 hPa)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                // Area fill under pressure line
                ForEach(weather.hourly) { hour in
                    AreaMark(
                        x: .value("Time", hour.time),
                        y: .value("Pressure", hour.pressure)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.indigo.opacity(0.3), .indigo.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Pressure line
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Pressure", hour.pressure)
                    )
                    .foregroundStyle(.indigo)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Now indicator
                nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                // Current value dot
                if let current = interpolatedCurrentValue(hourly: weather.hourly, keyPath: \.pressure) {
                    currentValuePoint(time: current.time, value: current.value, yLabel: "Pressure", color: .indigo)
                }
            }
            .chartYScale(domain: pressureRange)
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
                            Text("\(Int(v))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
            .frame(height: 180)

                // Chart band legend
                HStack(spacing: DesignTokens.spaceMD) {
                    LegendDot(color: .blue,   label: "Low (<1009)")
                    LegendDot(color: .green,  label: "Normal (1009–1022)")
                    LegendDot(color: .orange, label: "High (>1022)")
                }
            }
        }
    }
}
