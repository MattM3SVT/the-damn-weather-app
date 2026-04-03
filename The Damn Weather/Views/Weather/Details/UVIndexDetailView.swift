import SwiftUI
import Charts
import WeatherShared

/// Apple Weather-style UV Index detail page with gauge and daily strip.
struct UVIndexDetailView: View {
    let weather: WeatherSnapshot

    private var uvValue: Int { weather.current.uvIndex }
    private var uvLevel: String { Double(uvValue).uvLevel }

    private var description: String {
        switch uvValue {
        case 0...2:
            return "Low UV right now. You can go outside without turning into a lobster. Enjoy this rare moment."
        case 3...5:
            return "Moderate UV — sunscreen is a good idea if you'll be out for a while. Your skin will thank you later."
        case 6...7:
            return "High UV levels. Slap on SPF 30+ and find some shade, especially between 10 AM and 4 PM."
        case 8...10:
            return "Very high UV. Seriously, wear sunscreen, a hat, and sunglasses. The sun is not messing around today."
        default:
            return "Extreme UV levels. Stay inside if you can. If you can't, SPF 50+, protective clothing, and constant shade."
        }
    }

    private var gaugeColor: Color {
        switch uvValue {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }

    var body: some View {
        WeatherDetailPage(
            icon: "sun.max.fill",
            title: "UV Index",
            currentValue: "\(uvValue)",
            subtitle: uvLevel,
            description: description,
            accentColor: gaugeColor
        ) {
            Chart {
                ForEach(weather.hourly) { hour in
                    BarMark(
                        x: .value("Time", hour.time),
                        y: .value("UV", hour.uvIndex)
                    )
                    .foregroundStyle(uvBarColor(for: hour.uvIndex))
                }
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
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                }
            }
        } dailyStrip: {
            // UV gauge at top
            VStack(spacing: DesignTokens.spaceSM) {
                UVGauge(value: uvValue)
                    .frame(height: 24)
                    .padding(.bottom, DesignTokens.spaceSM)

                Divider().overlay(Color.white.opacity(0.05))

                ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                    HStack {
                        Text(day.date.dayLabel(index: index))
                            .font(.system(size: DesignTokens.smallSize, weight: .medium))
                            .frame(width: 60, alignment: .leading)

                        UVGauge(value: day.uvIndexMax)
                            .frame(height: 6)

                        Text("\(day.uvIndexMax)")
                            .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    if index < weather.daily.count - 1 {
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }

    private func uvBarColor(for value: Int) -> Color {
        switch value {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }
}

/// UV Index gauge bar — gradient from green to purple
struct UVGauge: View {
    let value: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .orange, .red, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(0.3)

                // Filled portion
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .orange, .red, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1, Double(value) / 11.0))

                // Indicator dot
                Circle()
                    .fill(.white)
                    .frame(width: geo.size.height + 4, height: geo.size.height + 4)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: max(0, geo.size.width * min(1, Double(value) / 11.0) - (geo.size.height + 4) / 2))
            }
        }
    }
}
