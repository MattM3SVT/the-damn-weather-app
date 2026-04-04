import SwiftUI
import Charts

/// Minute-by-minute precipitation chart using Swift Charts.
/// This is a WeatherKit-exclusive feature not available on the website.
struct PrecipitationChart: View {
    let data: [MinutePrecipitationPoint]

    private var maxIntensity: Double {
        data.map(\.intensity).max() ?? 0.1
    }

    private var hasPrecipitation: Bool {
        data.contains { $0.intensity > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spaceMD) {
            HStack {
                Image(systemName: "cloud.rain.fill")
                    .foregroundStyle(.blue)
                Text("Next Hour")
                    .font(.system(size: DesignTokens.sectionTitleSize, weight: .semibold))
            }

            GlassCard {
                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                    if hasPrecipitation {
                        Text("Precipitation expected")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Chart(data) { point in
                            AreaMark(
                                x: .value("Time", point.time),
                                y: .value("Intensity", point.intensity)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.blue.opacity(0.6), .blue.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Time", point.time),
                                y: .value("Intensity", point.intensity)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                                AxisValueLabel(format: .dateTime.minute())
                                    .foregroundStyle(.secondary)
                                AxisGridLine().foregroundStyle(.white.opacity(0.1))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: [0, 0.1, 0.3, 0.5]) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(intensityLabel(for: v))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                AxisGridLine().foregroundStyle(.white.opacity(0.1))
                            }
                        }
                        .frame(height: 120)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("No precipitation expected in the next hour")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func intensityLabel(for value: Double) -> String {
        switch value {
        case 0: return "None"
        case ...0.1: return "Light"
        case ...0.3: return "Moderate"
        default: return "Heavy"
        }
    }
}
