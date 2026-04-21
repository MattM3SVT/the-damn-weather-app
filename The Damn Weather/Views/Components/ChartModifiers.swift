import SwiftUI
import Charts

// MARK: - Now Indicator

/// Vertical "Now" line for 24-hour charts.
@ChartContentBuilder
func nowIndicator(hourlyTimes: [Date]) -> some ChartContent {
    let now = Date()
    if let first = hourlyTimes.first, let last = hourlyTimes.last,
       now >= first, now <= last {
        RuleMark(x: .value("Now", now))
            .foregroundStyle(.white.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .center, spacing: 4) {
                Text("Now")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
    }
}

// MARK: - Current Value Point

/// Apple Weather-style highlighted dot at the current time position.
@ChartContentBuilder
func currentValuePoint(time: Date, value: Double, yLabel: String, color: Color) -> some ChartContent {
    PointMark(
        x: .value("Now", time),
        y: .value(yLabel, value)
    )
    .symbolSize(50)
    .foregroundStyle(color)

    PointMark(
        x: .value("Now", time),
        y: .value(yLabel, value)
    )
    .symbolSize(20)
    .foregroundStyle(.white)
}

// MARK: - Interpolation

/// Linearly interpolates a value at the current time between surrounding hourly points.
func interpolatedCurrentValue(
    hourly: [HourlyForecastPoint],
    keyPath: KeyPath<HourlyForecastPoint, Double>
) -> (time: Date, value: Double)? {
    let now = Date()
    guard let first = hourly.first, let last = hourly.last,
          now >= first.time, now <= last.time else { return nil }

    // Find the two surrounding points
    var before: HourlyForecastPoint?
    var after: HourlyForecastPoint?
    for point in hourly {
        if point.time <= now {
            before = point
        } else {
            after = point
            break
        }
    }

    guard let b = before, let a = after else {
        // Exact match or edge case — return nearest
        if let b = before { return (now, b[keyPath: keyPath]) }
        if let a = after { return (now, a[keyPath: keyPath]) }
        return nil
    }

    let totalInterval = a.time.timeIntervalSince(b.time)
    guard totalInterval > 0 else { return (now, b[keyPath: keyPath]) }

    let fraction = now.timeIntervalSince(b.time) / totalInterval
    let interpolated = b[keyPath: keyPath] + (a[keyPath: keyPath] - b[keyPath: keyPath]) * fraction
    return (now, interpolated)
}

/// Interpolated value with unit conversion (for temperature charts).
func interpolatedCurrentValueConverted(
    hourly: [HourlyForecastPoint],
    keyPath: KeyPath<HourlyForecastPoint, Double>,
    convert: (Double) -> Double
) -> (time: Date, value: Double)? {
    guard let result = interpolatedCurrentValue(hourly: hourly, keyPath: keyPath) else { return nil }
    return (result.time, convert(result.value))
}

// MARK: - Chart Legend

/// Compact legend for multi-series charts.
struct ChartLegend: View {
    let items: [(color: Color, label: String, dashed: Bool)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    // Line segment
                    if item.dashed {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 4))
                            path.addLine(to: CGPoint(x: 16, y: 4))
                        }
                        .stroke(item.color, style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
                        .frame(width: 16, height: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(item.color)
                            .frame(width: 16, height: 3)
                    }

                    Text(item.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
