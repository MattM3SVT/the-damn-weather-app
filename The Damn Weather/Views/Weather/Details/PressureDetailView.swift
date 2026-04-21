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
        // Trail every variant with the same one-line reference so the chart can
        // stay uncluttered — normal range, standard pressure, and what "low"
        // or "high" means live in prose, not as on-chart legends.
        let reference = "Normal range is 1009–1022 hPa; standard at sea level is 1013 hPa."
        switch trend {
        case "Rising":
            return "Barometric pressure is rising, which usually means improving conditions. Clear skies might be on the way — don't get too excited though. \(reference)"
        case "Falling":
            return "Pressure is dropping, which often signals incoming weather changes. Clouds, rain, or general atmospheric drama could be headed your way. \(reference)"
        default:
            return "Pressure is holding steady at \(appState.pressureUnit.format(weather.current.pressure)). Stable conditions — the atmosphere is taking a day off. \(reference)"
        }
    }

    private var pressureRange: ClosedRange<Double> {
        let vals = weather.hourly.map(\.pressure)
        let minVal = vals.min() ?? 1010
        let maxVal = vals.max() ?? 1016
        // Snap bounds to even hPa so every axis gridline — including the bottom
        // one — coincides with a labeled tick. Otherwise Swift Charts' auto-stride
        // skips the domain floor, and the area fill bleeds into the unlabeled
        // gap below the lowest label.
        let lo = floor(minVal / 2) * 2 - 2
        let hi = ceil(maxVal / 2) * 2 + 2
        return lo...hi
    }

    private var pressureAxisValues: [Double] {
        Array(stride(from: pressureRange.lowerBound,
                     through: pressureRange.upperBound,
                     by: 2))
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
                // Area fill under pressure line.
                // yStart is pinned to the domain's lower bound so the fill can't
                // extend below the lowest gridline into the x-axis label strip.
                // This also lets the top→bottom gradient fade across the *visible*
                // band instead of (0, line) — otherwise the visible slice sits at
                // near-uniform high opacity because the default baseline is y=0.
                ForEach(weather.hourly) { hour in
                    AreaMark(
                        x: .value("Time", hour.time),
                        yStart: .value("Pressure", pressureRange.lowerBound),
                        yEnd: .value("Pressure", hour.pressure)
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
                AxisMarks(position: .trailing, values: pressureAxisValues) { value in
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
            }
        }
    }
}
