import SwiftUI
import Combine
import WeatherShared

/// Animated weather icon that matches the website's SVG animations.
/// All dimensions are designed at 100pt base and scale proportionally.
struct AnimatedWeatherIcon: View {
    let condition: WeatherConditionTag
    let isDay: Bool
    var size: CGFloat = 100

    private var scale: CGFloat { size / 100 }

    var body: some View {
        Group {
            switch condition {
            case .clear:
                if isDay {
                    SunIcon(scale: scale)
                } else {
                    MoonIcon(scale: scale)
                }
            case .partlyCloudy:
                if isDay {
                    PartlyCloudyDayIcon(scale: scale)
                } else {
                    PartlyCloudyNightIcon(scale: scale)
                }
            case .cloudy, .any:
                CloudyIcon(scale: scale)
            case .fog:
                FogIcon(scale: scale)
            case .drizzle:
                DrizzleIcon(scale: scale)
            case .rain:
                RainIcon(scale: scale)
            case .heavyRain:
                RainIcon(scale: scale, heavy: true)
            case .snow:
                SnowIcon(scale: scale)
            case .heavySnow:
                SnowIcon(scale: scale, heavy: true)
            case .freezingRain:
                SleetIcon(scale: scale)
            case .thunderstorm:
                ThunderstormIcon(scale: scale)
            case .wind:
                WindIcon(scale: scale)
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

// MARK: - Color Palette

private enum IconColors {
    static let sunGold = Color(red: 0.984, green: 0.749, blue: 0.141)       // #fbbf24
    static let sunOrange = Color(red: 0.961, green: 0.620, blue: 0.043)     // #f59e0b
    static let moonBlue = Color(red: 0.525, green: 0.765, blue: 0.859)      // #86c3db
    static let moonDark = Color(red: 0.369, green: 0.686, blue: 0.812)      // #5eafcf
    static let cloudWhite = Color(red: 0.953, green: 0.969, blue: 0.996)    // #f3f7fe
    static let cloudBlue = Color(red: 0.871, green: 0.918, blue: 0.984)     // #deeafb
    static let cloudStroke = Color(red: 0.82, green: 0.87, blue: 0.95)      // #d1deF3
    static let rainBlue = Color(red: 0.043, green: 0.396, blue: 0.929)      // #0b65ed
    static let rainDark = Color(red: 0.035, green: 0.314, blue: 0.737)      // #0950bc
    static let snowBlue = Color(red: 0.525, green: 0.765, blue: 0.859)      // #86c3db
    static let boltYellow = Color(red: 0.969, green: 0.698, blue: 0.231)    // #f7b23b
    static let windGray = Color(red: 0.831, green: 0.843, blue: 0.867)      // #d4d7dd
    static let windDark = Color(red: 0.745, green: 0.757, blue: 0.776)      // #bec1c6
}

// MARK: - Cloud Shape (reused by many icons)

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        // Natural cloud using cubic curves, matching the SVG style
        // Start at bottom-left
        let bottomY = h * 0.85
        let leftX = w * 0.12
        let rightX = w * 0.88

        path.move(to: CGPoint(x: leftX, y: bottomY))

        // Bottom edge (flat)
        path.addLine(to: CGPoint(x: rightX, y: bottomY))

        // Right side bump up
        path.addCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.38),
            control1: CGPoint(x: w * 1.0, y: bottomY),
            control2: CGPoint(x: w * 0.98, y: h * 0.38)
        )

        // Top bump (tallest part)
        path.addCurve(
            to: CGPoint(x: w * 0.42, y: h * 0.12),
            control1: CGPoint(x: w * 0.72, y: h * 0.08),
            control2: CGPoint(x: w * 0.52, y: h * 0.05)
        )

        // Left bump
        path.addCurve(
            to: CGPoint(x: w * 0.15, y: h * 0.52),
            control1: CGPoint(x: w * 0.28, y: h * 0.15),
            control2: CGPoint(x: w * 0.12, y: h * 0.30)
        )

        // Back to bottom-left
        path.addCurve(
            to: CGPoint(x: leftX, y: bottomY),
            control1: CGPoint(x: w * 0.02, y: h * 0.65),
            control2: CGPoint(x: w * 0.0, y: bottomY)
        )

        path.closeSubpath()
        return path
    }
}

private struct CloudView: View {
    let scale: CGFloat
    var width: CGFloat = 85
    var height: CGFloat = 55

    var body: some View {
        CloudShape()
            .fill(
                LinearGradient(
                    colors: [IconColors.cloudWhite, IconColors.cloudBlue],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                CloudShape()
                    .stroke(IconColors.cloudStroke, lineWidth: 1.5 * scale)
            )
            .frame(width: width * scale, height: height * scale)
    }
}

// MARK: - Sun Icon (clear-day)

private struct SunIcon: View {
    let scale: CGFloat
    @State private var rotating = false

    var body: some View {
        ZStack {
            // Rays (rotate)
            SunRays(scale: scale, rayLength: 14, rayWidth: 5, radius: 40)
                .rotationEffect(.degrees(rotating ? 45 : 0))
                .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: rotating)

            // Sun circle (fixed)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [IconColors.sunGold, IconColors.sunOrange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(IconColors.sunOrange.opacity(0.6), lineWidth: 2 * scale))
                .frame(width: 44 * scale, height: 44 * scale)
        }
        .onAppear { rotating = true }
    }
}

private struct SunRays: View {
    let scale: CGFloat
    var rayLength: CGFloat = 14
    var rayWidth: CGFloat = 5
    var radius: CGFloat = 40

    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                Capsule()
                    .fill(IconColors.sunGold)
                    .frame(width: rayWidth * scale, height: rayLength * scale)
                    .offset(y: -radius * scale)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
    }
}

// MARK: - Moon Icon (clear-night)

private struct MoonIcon: View {
    let scale: CGFloat
    @State private var rocking = false

    var body: some View {
        CrescentMoon()
            .fill(
                LinearGradient(
                    colors: [IconColors.moonBlue, IconColors.moonDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                CrescentMoon()
                    .stroke(Color(red: 0.447, green: 0.725, blue: 0.835), lineWidth: 2 * scale) // #72b9d5
            )
            .frame(width: 55 * scale, height: 55 * scale)
            .rotationEffect(.degrees(rocking ? 9 : -15))
            .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: rocking)
            .onAppear { rocking = true }
    }
}

/// Crescent moon shape matching the website SVG.
/// Full moon circle with a second circle subtracted (offset upper-right) to carve the crescent.
private struct CrescentMoon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        // Full moon circle
        let moonRect = CGRect(x: w * 0.05, y: h * 0.05, width: w * 0.85, height: h * 0.85)
        let moonCircle = Path(ellipseIn: moonRect)

        // Cutout circle — shifted right and up to carve the crescent
        let cutRect = CGRect(x: w * 0.35, y: -h * 0.1, width: w * 0.8, height: h * 0.8)
        let cutCircle = Path(ellipseIn: cutRect)

        return moonCircle.subtracting(cutCircle)
    }
}

// MARK: - Partly Cloudy Day

private struct PartlyCloudyDayIcon: View {
    let scale: CGFloat
    @State private var rotating = false

    var body: some View {
        ZStack {
            // Sun (behind, offset up-left)
            ZStack {
                SunRays(scale: scale * 0.55, rayLength: 12, rayWidth: 4.5, radius: 34)
                    .rotationEffect(.degrees(rotating ? 45 : 0))
                    .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: rotating)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [IconColors.sunGold, IconColors.sunOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22 * scale, height: 22 * scale)
            }
            .offset(x: -18 * scale, y: -16 * scale)

            // Cloud (in front)
            CloudView(scale: scale, width: 72, height: 46)
                .offset(x: 6 * scale, y: 10 * scale)
        }
        .onAppear { rotating = true }
    }
}

// MARK: - Partly Cloudy Night

private struct PartlyCloudyNightIcon: View {
    let scale: CGFloat
    @State private var rocking = false

    var body: some View {
        ZStack {
            // Moon (behind, offset up-left)
            CrescentMoon()
                .fill(
                    LinearGradient(
                        colors: [IconColors.moonBlue, IconColors.moonDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    CrescentMoon()
                        .stroke(Color(red: 0.447, green: 0.725, blue: 0.835), lineWidth: 1.5 * scale)
                )
                .frame(width: 36 * scale, height: 36 * scale)
                .rotationEffect(.degrees(rocking ? 9 : -15))
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: rocking)
                .offset(x: -20 * scale, y: -16 * scale)

            // Cloud (in front)
            CloudView(scale: scale, width: 72, height: 46)
                .offset(x: 6 * scale, y: 10 * scale)
        }
        .onAppear { rocking = true }
    }
}

// MARK: - Cloudy

private struct CloudyIcon: View {
    let scale: CGFloat
    @State private var swaying = false

    var body: some View {
        CloudView(scale: scale)
            .offset(x: swaying ? 6 * scale : -6 * scale)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: swaying)
            .onAppear { swaying = true }
    }
}

// MARK: - Fog

private struct FogIcon: View {
    let scale: CGFloat
    @State private var sliding = false

    var body: some View {
        VStack(spacing: 5 * scale) {
            CloudView(scale: scale, width: 75, height: 48)

            VStack(spacing: 7 * scale) {
                Capsule()
                    .fill(LinearGradient(colors: [IconColors.windGray, IconColors.windDark],
                                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 60 * scale, height: 5 * scale)
                    .offset(x: sliding ? 8 * scale : -8 * scale)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: sliding)

                Capsule()
                    .fill(LinearGradient(colors: [IconColors.windDark, IconColors.windGray],
                                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 48 * scale, height: 5 * scale)
                    .offset(x: sliding ? -8 * scale : 8 * scale)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: sliding)
            }
        }
        .onAppear { sliding = true }
    }
}

// MARK: - Rain

private struct RainIcon: View {
    let scale: CGFloat
    var heavy: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            CloudView(scale: scale, width: 75, height: 48)
                .offset(y: 2 * scale)

            HStack(spacing: heavy ? 10 * scale : 14 * scale) {
                RainDrop(scale: scale, delay: 0, duration: heavy ? 0.67 : 1.0, heavy: heavy)
                RainDrop(scale: scale, delay: heavy ? 0.22 : 0.33, duration: heavy ? 0.67 : 1.0, heavy: heavy)
                RainDrop(scale: scale, delay: heavy ? 0.44 : 0.67, duration: heavy ? 0.67 : 1.0, heavy: heavy)
            }
            .offset(y: -4 * scale)
        }
    }
}

private struct RainDrop: View {
    let scale: CGFloat
    let delay: Double
    let duration: Double
    var heavy: Bool = false

    @State private var falling = false
    @State private var visible = false

    private var dropHeight: CGFloat { heavy ? 14 : 10 }
    private var dropWidth: CGFloat { heavy ? 4 : 3 }
    private var fallDistance: CGFloat { 26 }

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [IconColors.rainBlue, IconColors.rainDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: dropWidth * scale, height: dropHeight * scale)
            .offset(y: falling ? fallDistance * scale : 0)
            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: falling)
            .opacity(visible ? 0 : 1)
            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: visible)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    startAnimation()
                }
            }
    }

    private func startAnimation() {
        falling = true
        visible = true
    }
}

// MARK: - Drizzle

private struct DrizzleIcon: View {
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            CloudView(scale: scale, width: 75, height: 48)
                .offset(y: 2 * scale)

            HStack(spacing: 16 * scale) {
                RainDrop(scale: scale, delay: 0, duration: 1.2)
                RainDrop(scale: scale, delay: 0.4, duration: 1.2)
                RainDrop(scale: scale, delay: 0.8, duration: 1.2)
            }
            .offset(y: -4 * scale)
        }
    }
}

// MARK: - Snow

private struct SnowIcon: View {
    let scale: CGFloat
    var heavy: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            CloudView(scale: scale, width: 75, height: 48)
                .offset(y: 2 * scale)

            HStack(spacing: heavy ? 8 * scale : 12 * scale) {
                Snowflake(scale: scale, delay: 0)
                Snowflake(scale: scale, delay: 0.83)
                Snowflake(scale: scale, delay: 1.66)
                if heavy {
                    Snowflake(scale: scale, delay: 0.4)
                }
            }
            .offset(y: -4 * scale)
        }
    }
}

private struct Snowflake: View {
    let scale: CGFloat
    let delay: Double

    @State private var spinning = false
    @State private var falling = false
    @State private var visible = false

    var body: some View {
        SnowflakeShape()
            .stroke(IconColors.snowBlue, lineWidth: 1.5 * scale)
            .frame(width: 10 * scale, height: 10 * scale)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spinning)
            .offset(y: falling ? 24 * scale : 0)
            .animation(.easeIn(duration: 2).repeatForever(autoreverses: false), value: falling)
            .opacity(visible ? 0 : 1)
            .animation(.easeIn(duration: 2).repeatForever(autoreverses: false), value: visible)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    spinning = true
                    falling = true
                    visible = true
                }
            }
    }
}

private struct SnowflakeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for i in 0..<6 {
            let angle = Double(i) * 60.0 * .pi / 180.0
            let endX = center.x + CGFloat(cos(angle)) * radius
            let endY = center.y + CGFloat(sin(angle)) * radius
            path.move(to: center)
            path.addLine(to: CGPoint(x: endX, y: endY))

            // Small branches at 60% radius
            let branchStart = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius * 0.6,
                y: center.y + CGFloat(sin(angle)) * radius * 0.6
            )
            for dir in [-1.0, 1.0] {
                let branchAngle = angle + dir * 45 * .pi / 180
                let branchEnd = CGPoint(
                    x: branchStart.x + CGFloat(cos(branchAngle)) * radius * 0.3,
                    y: branchStart.y + CGFloat(sin(branchAngle)) * radius * 0.3
                )
                path.move(to: branchStart)
                path.addLine(to: branchEnd)
            }
        }

        return path
    }
}

// MARK: - Sleet (Freezing Rain)

private struct SleetIcon: View {
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            CloudView(scale: scale, width: 75, height: 48)
                .offset(y: 2 * scale)

            HStack(spacing: 10 * scale) {
                RainDrop(scale: scale, delay: 0, duration: 0.8)
                Snowflake(scale: scale, delay: 0.5)
                RainDrop(scale: scale, delay: 0.4, duration: 0.8)
                Snowflake(scale: scale, delay: 1.0)
            }
            .offset(y: -4 * scale)
        }
    }
}

// MARK: - Thunderstorm

private struct ThunderstormIcon: View {
    let scale: CGFloat
    @State private var flickerPhase: Int = 0
    @State private var timer: Timer.TimerPublisher = Timer.publish(every: 0.167, on: .main, in: .common)
    @State private var timerConnection: Cancellable?

    private let pattern: [Double] = [1, 1, 0, 1, 0, 1, 0, 1]

    var body: some View {
        VStack(spacing: -4 * scale) {
            CloudView(scale: scale, width: 75, height: 48)

            LightningBolt(scale: scale)
                .opacity(pattern[flickerPhase % pattern.count])
        }
        .onReceive(timer) { _ in
            flickerPhase = (flickerPhase + 1) % pattern.count
        }
        .onAppear {
            timerConnection = timer.connect()
        }
        .onDisappear {
            timerConnection?.cancel()
        }
    }
}

private struct LightningBolt: View {
    let scale: CGFloat

    var body: some View {
        LightningShape()
            .fill(
                LinearGradient(
                    colors: [IconColors.boltYellow, IconColors.sunOrange],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(LightningShape().stroke(IconColors.sunOrange.opacity(0.6), lineWidth: 1.5 * scale))
            .frame(width: 20 * scale, height: 34 * scale)
    }
}

private struct LightningShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        path.move(to: CGPoint(x: w * 0.55, y: 0))
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.3, y: h))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.8, y: 0))
        path.closeSubpath()

        return path
    }
}

// MARK: - Wind

private struct WindIcon: View {
    let scale: CGFloat
    @State private var dashPhase1: CGFloat = 0
    @State private var dashPhase2: CGFloat = 0

    // Dash pattern: visible segment + gap — creates flowing dashes along the path
    private var dashLength: CGFloat { 28 * scale }
    private var gapLength: CGFloat { 18 * scale }
    private var strokeWidth: CGFloat { 5 * scale }

    var body: some View {
        ZStack {
            // Top wind line — longer, positioned higher
            WindWave()
                .stroke(
                    LinearGradient(
                        colors: [IconColors.windGray, IconColors.windDark],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        dash: [dashLength, gapLength],
                        dashPhase: dashPhase1
                    )
                )
                .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: dashPhase1)
                .frame(width: 75 * scale, height: 16 * scale)
                .offset(y: -14 * scale)

            // Bottom wind line — shorter, offset down and left
            WindWave()
                .stroke(
                    LinearGradient(
                        colors: [IconColors.windDark, IconColors.windGray],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: strokeWidth * 0.9,
                        lineCap: .round,
                        dash: [dashLength * 0.8, gapLength * 0.8],
                        dashPhase: dashPhase2
                    )
                )
                .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: dashPhase2)
                .frame(width: 58 * scale, height: 14 * scale)
                .offset(x: -8 * scale, y: 14 * scale)
        }
        .onAppear {
            dashPhase1 = -(dashLength + gapLength) * 6
            dashPhase2 = -(dashLength * 0.8 + gapLength * 0.8) * 5
        }
    }
}

/// Smooth S-curve wave that flows left to right — matches the fluid feel of the website's wind.
private struct WindWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Start on the left at mid-height
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        // Gentle S-curve: control points push up then down
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.3, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.7, y: rect.maxY)
        )
        return path
    }
}

// MARK: - Debug Preview Grid

/// Shows all weather icon variants in a grid. Access via Settings or debug menu.
struct WeatherIconPreviewGrid: View {
    let size: CGFloat

    private let conditions: [(WeatherConditionTag, String)] = [
        (.clear, "Clear Day"),
        (.clear, "Clear Night"),
        (.partlyCloudy, "Partly Cloudy Day"),
        (.partlyCloudy, "Partly Cloudy Night"),
        (.cloudy, "Cloudy"),
        (.fog, "Fog"),
        (.drizzle, "Drizzle"),
        (.rain, "Rain"),
        (.heavyRain, "Heavy Rain"),
        (.snow, "Snow"),
        (.heavySnow, "Heavy Snow"),
        (.freezingRain, "Sleet"),
        (.thunderstorm, "Thunderstorm"),
        (.wind, "Wind"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 40))], spacing: 20) {
            ForEach(Array(conditions.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 8) {
                    AnimatedWeatherIcon(
                        condition: item.0,
                        isDay: index <= 1 ? index == 0 : (index == 2 ? true : (index == 3 ? false : true)),
                        size: size
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.05))
                    )

                    Text(item.1)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
