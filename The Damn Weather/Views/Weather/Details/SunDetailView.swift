import SwiftUI
import WeatherShared

/// Apple Weather-style sunrise/sunset detail page with sun arc and daily times.
struct SunDetailView: View {
    let weather: WeatherSnapshot

    private var todaySunrise: Date? { weather.daily.first?.sunrise }
    private var todaySunset: Date? { weather.daily.first?.sunset }

    private var dayLength: String {
        guard let rise = todaySunrise, let set = todaySunset else { return "--" }
        let seconds = set.timeIntervalSince(rise)
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private var sunProgress: Double {
        guard let rise = todaySunrise, let set = todaySunset else { return 0 }
        let now = Date()
        if now < rise { return 0 }
        if now > set { return 1 }
        return now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
    }

    private var description: String {
        let progress = sunProgress
        if progress <= 0 {
            return "The sun hasn't risen yet. Patience. It'll get here when it gets here."
        } else if progress >= 1 {
            return "The sun has set. Day length was \(dayLength). Time to accept the darkness."
        } else if progress < 0.2 {
            return "Early morning light. The sun just rose — day length today is \(dayLength)."
        } else if progress > 0.8 {
            return "Getting close to sunset. Enjoy the last bits of daylight — \(dayLength) total today."
        } else {
            return "Sun is up and doing its thing. Total daylight today: \(dayLength)."
        }
    }

    var body: some View {
        WeatherDetailPage(
            icon: weather.current.isDay ? "sunrise.fill" : "sunset.fill",
            title: "Sunrise & Sunset",
            currentValue: dayLength,
            subtitle: "of daylight today",
            description: description,
            accentColor: .yellow
        ) {
            // Sun arc visualization
            SunArcView(
                sunrise: todaySunrise ?? Date(),
                sunset: todaySunset ?? Date(),
                progress: sunProgress
            )
        } dailyStrip: {
            ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text(day.date.dayLabel(index: index))
                        .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        .frame(width: 60, alignment: .leading)

                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                        .frame(width: 20)

                    Text(day.sunrise.timeString(timezone: weather.timezone))
                        .font(.system(size: DesignTokens.captionSize))
                        .frame(width: 70, alignment: .leading)

                    Spacer()

                    Image(systemName: "sunset.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    Text(day.sunset.timeString(timezone: weather.timezone))
                        .font(.system(size: DesignTokens.captionSize))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 4)

                if index < weather.daily.count - 1 {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }
}

/// Sun arc visualization showing the sun's path across the sky
struct SunArcView: View {
    let sunrise: Date
    let sunset: Date
    let progress: Double

    /// Evaluate the quadratic Bezier y-position for a given t.
    /// Control offset `c` means the control point is at `baseY - c`.
    /// Bezier formula: y = baseY - c * 2 * t * (1 - t)
    private static func arcY(baseY: Double, controlOffset c: Double, t: Double) -> Double {
        baseY - c * 2 * t * (1 - t)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let controlOffset = height * 0.7  // How far above baseY the control point sits
            let baseY = height * 0.85

            ZStack {
                // Horizon line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baseY))
                    path.addLine(to: CGPoint(x: width, y: baseY))
                }
                .stroke(.white.opacity(0.15), lineWidth: 1)

                // Full dashed arc path
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baseY))
                    path.addQuadCurve(
                        to: CGPoint(x: width, y: baseY),
                        control: CGPoint(x: width / 2, y: baseY - controlOffset)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [.yellow.opacity(0.2), .yellow.opacity(0.5), .orange.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )

                // Daylight glow fill under lit arc
                if progress > 0 && progress < 1 {
                    Path { path in
                        let steps = Int(progress * 50)
                        for i in 0...steps {
                            let t = Double(i) / 50.0
                            let x = t * width
                            let y = Self.arcY(baseY: baseY, controlOffset: controlOffset, t: t)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        // Close path down to horizon
                        let endX = progress * width
                        path.addLine(to: CGPoint(x: endX, y: baseY))
                        path.addLine(to: CGPoint(x: 0, y: baseY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [.yellow.opacity(0.15), .yellow.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Lit portion of the arc (matches Bezier exactly)
                if progress > 0 && progress < 1 {
                    Path { path in
                        let steps = Int(progress * 50)
                        for i in 0...steps {
                            let t = Double(i) / 50.0
                            let x = t * width
                            let y = Self.arcY(baseY: baseY, controlOffset: controlOffset, t: t)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }

                // Sun position dot
                if progress > 0 && progress < 1 {
                    let sunX = progress * width
                    let sunY = Self.arcY(baseY: baseY, controlOffset: controlOffset, t: progress)

                    Circle()
                        .fill(.yellow)
                        .frame(width: 16, height: 16)
                        .shadow(color: .yellow.opacity(0.5), radius: 8)
                        .position(x: sunX, y: sunY)
                }

                // Sunrise label
                VStack(spacing: 2) {
                    Text("Sunrise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(sunrise.timeString())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
                .position(x: 40, y: baseY + 20)

                // Sunset label
                VStack(spacing: 2) {
                    Text("Sunset")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(sunset.timeString())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .position(x: width - 40, y: baseY + 20)
            }
        }
    }
}
