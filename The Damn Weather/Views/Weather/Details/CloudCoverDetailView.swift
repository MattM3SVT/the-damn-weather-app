import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style cloud cover detail page with 24-hour area chart.
struct CloudCoverDetailView: View {
    let weather: WeatherSnapshot

    private var cloudPct: Double { weather.current.cloudCover }

    private var coverageLevel: String {
        switch cloudPct {
        case ..<10: return "Clear"
        case ..<25: return "Mostly Clear"
        case ..<50: return "Partly Cloudy"
        case ..<75: return "Mostly Cloudy"
        case ..<90: return "Cloudy"
        default: return "Overcast"
        }
    }

    private var description: String {
        switch cloudPct {
        case ..<10:
            return "Barely a cloud in the sky. The sun is having a field day — literally. Enjoy the unobstructed celestial view while it lasts."
        case ..<25:
            return "Mostly clear skies with a few decorative clouds. The atmosphere is showing off — a blue canvas with just a touch of white."
        case ..<50:
            return "Partly cloudy — the sun is playing peek-a-boo. You'll get some shade breaks whether you want them or not."
        case ..<75:
            return "Mostly cloudy. The clouds are winning the territory war up there. The sun makes occasional appearances like a reluctant celebrity."
        case ..<90:
            return "Heavy cloud cover. The sky is wearing a thick gray blanket. The sun is somewhere up there, theoretically."
        default:
            return "Complete overcast. The sky has pulled the curtains shut. If you forgot what the sun looks like, this won't help you remember."
        }
    }

    var body: some View {
        WeatherDetailPage(
            icon: "cloud.fill",
            title: "Cloud Cover",
            currentValue: cloudPct.percentString,
            subtitle: coverageLevel,
            description: description,
            accentColor: .gray
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                Chart {
                // Zone annotations
                RectangleMark(
                    xStart: .value("Start", weather.hourly.first?.time ?? Date()),
                    xEnd: .value("End", weather.hourly.last?.time ?? Date()),
                    yStart: .value("Low", 75),
                    yEnd: .value("High", 100)
                )
                .foregroundStyle(.white.opacity(0.04))

                // Area fill — heavier opacity to mimic cloud density
                ForEach(weather.hourly) { hour in
                    AreaMark(
                        x: .value("Time", hour.time),
                        y: .value("Cloud Cover", hour.cloudCover)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Cloud cover line
                ForEach(weather.hourly) { hour in
                    LineMark(
                        x: .value("Time", hour.time),
                        y: .value("Cloud Cover", hour.cloudCover)
                    )
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Now indicator
                nowIndicator(hourlyTimes: weather.hourly.map(\.time))

                // Current value dot
                if let current = interpolatedCurrentValue(hourly: weather.hourly, keyPath: \.cloudCover) {
                    currentValuePoint(time: current.time, value: current.value, yLabel: "Cloud Cover", color: .white)
                }
            }
            // Y-domain extends to 110 to create visual headroom above 100%.
            // Without this, a line at 100% rides the plot's top edge and
            // crowds the "Now" pill. Axis labels are pinned to 0–100.
            .chartYScale(domain: 0...110)
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
            .frame(height: 180)

                // Chart band legend
                HStack(spacing: DesignTokens.spaceSM) {
                    LegendDot(color: .yellow,               label: "Clear (0–25%)")
                    LegendDot(color: .white.opacity(0.7),   label: "Partly (25–50%)")
                    LegendDot(color: .white.opacity(0.5),   label: "Mostly (50–75%)")
                    LegendDot(color: .white.opacity(0.3),   label: "Overcast (75%+)")
                }
            }
        }
    }
}
