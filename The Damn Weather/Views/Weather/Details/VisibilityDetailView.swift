import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style visibility detail page with 24-hour chart and quality zones.
struct VisibilityDetailView: View {
    let weather: WeatherSnapshot
    @Environment(AppState.self) private var appState

    private var visibilityMiles: Double { weather.current.visibility }

    private var description: String {
        switch visibilityMiles {
        case ..<1:
            return "Visibility is extremely poor right now. Fog, heavy rain, or some other atmospheric tantrum is making it hard to see. Drive carefully — or just don't."
        case ..<3:
            return "Poor visibility conditions. You can see a bit, but the atmosphere clearly doesn't want you to. Expect reduced conditions for the next few hours."
        case ..<6:
            return "Moderate visibility. Not great, not terrible. The kind of day where you can see where you're going but not much beyond that."
        case ..<10:
            return "Good visibility today. You can see things. Far things. The atmosphere is being cooperative for once."
        default:
            return "Excellent visibility — crystal clear out there. You can probably see the curvature of the Earth if you squint hard enough. Enjoy it."
        }
    }

    private var visibilityRange: ClosedRange<Double> {
        let vals = weather.hourly.map { appState.distanceUnit.convert($0.visibility) }
        let lo = max(0, (vals.min() ?? 0) - 1)
        let hi = (vals.max() ?? 15) + 1
        return lo...hi
    }

    var body: some View {
        WeatherDetailPage(
            icon: "eye.fill",
            title: "Visibility",
            currentValue: appState.distanceUnit.format(visibilityMiles),
            subtitle: visibilityMiles.visibilityDescription,
            description: description,
            accentColor: .mint
        ) {
            Chart {
                // Quality zone annotations
                RectangleMark(
                    yStart: .value("Low", 0),
                    yEnd: .value("High", appState.distanceUnit.convert(1))
                )
                .foregroundStyle(.red.opacity(0.06))

                RectangleMark(
                    yStart: .value("Low", appState.distanceUnit.convert(6)),
                    yEnd: .value("High", visibilityRange.upperBound)
                )
                .foregroundStyle(.green.opacity(0.04))

                // Area fill
                ForEach(weather.hourly) { hour in
                    AreaMark(
                        x: .value("Time", hour.time),
                        y: .value("Visibility", appState.distanceUnit.convert(hour.visibility))
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.mint.opacity(0.3), .mint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Visibility line
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Visibility", appState.distanceUnit.convert(hour.visibility))
                    )
                    .foregroundStyle(.mint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Now indicator
                nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                // Current value dot
                if let current = interpolatedCurrentValueConverted(
                    hourly: weather.hourly,
                    keyPath: \.visibility,
                    convert: { appState.distanceUnit.convert($0) }
                ) {
                    currentValuePoint(time: current.time, value: current.value, yLabel: "Visibility", color: .mint)
                }
            }
            .chartYScale(domain: visibilityRange)
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
                            Text("\(Int(v)) \(appState.distanceUnit.label)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
        } dailyStrip: {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                // Visibility quality legend
                HStack(spacing: DesignTokens.spaceLG) {
                    VStack(spacing: 4) {
                        Circle().fill(.red.opacity(0.6)).frame(width: 10, height: 10)
                        Text("Poor")
                            .font(.system(size: 11, weight: .medium))
                        Text("< 1 mi")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Circle().fill(.yellow.opacity(0.6)).frame(width: 10, height: 10)
                        Text("Moderate")
                            .font(.system(size: 11, weight: .medium))
                        Text("1–6 mi")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Circle().fill(.green.opacity(0.6)).frame(width: 10, height: 10)
                        Text("Good")
                            .font(.system(size: 11, weight: .medium))
                        Text("6–10 mi")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Circle().fill(.mint).frame(width: 10, height: 10)
                        Text("Excellent")
                            .font(.system(size: 11, weight: .medium))
                        Text("10+ mi")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().overlay(Color.white.opacity(0.05))

                // Current visibility highlight
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Visibility")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(visibilityMiles.visibilityDescription)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Spacer()
                    Text(appState.distanceUnit.format(visibilityMiles))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
            }
        }
    }
}
