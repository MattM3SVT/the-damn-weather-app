import SwiftUI
import WeatherShared

/// Apple Weather-style moon detail page with phase visualization and 10-day moon strip.
struct MoonDetailView: View {
    let weather: WeatherSnapshot

    private var moon: MoonPhaseData {
        weather.moonPhase ?? MoonPhaseData(phase: .newMoon, illumination: 0)
    }

    private var description: String {
        switch moon.phase {
        case .newMoon:
            return "New Moon — the moon is hiding. It's out there, it's just not in the mood to be seen. Great night for stargazing though."
        case .waxingCrescent:
            return "A thin sliver of moon is growing in the western sky after sunset. It's the moon's opening act — small but full of promise."
        case .firstQuarter:
            return "The moon is half-lit, like it couldn't decide whether to show up tonight. You're seeing the right half — the left half is on break."
        case .waxingGibbous:
            return "Almost full. The moon is getting its act together, shining brighter each night. It's the overachiever of the lunar cycle."
        case .fullMoon:
            return "Full Moon — the whole damn thing is lit up. Maximum illumination, maximum drama. Werewolves are having a great night."
        case .waningGibbous:
            return "Just past full, the moon is still impressively bright. It's the lunar equivalent of 'the party's winding down but the lights are still on.'"
        case .lastQuarter:
            return "Half-lit again, but now it's the left side showing. The moon rises around midnight — it's become a night owl."
        case .waningCrescent:
            return "A thin crescent visible in the early morning sky. The moon is wrapping up this cycle, barely visible — like it's sneaking out before dawn."
        }
    }

    var body: some View {
        WeatherDetailPage(
            icon: moon.phase.sfSymbol,
            title: "Moon",
            currentValue: moon.phase.rawValue,
            subtitle: "\(Int(moon.illumination * 100))% illuminated",
            description: description,
            accentColor: .yellow
        ) {
            // Custom moon visualization instead of a chart
            VStack(spacing: DesignTokens.spaceLG) {
                // Large moon icon
                Image(systemName: moon.phase.sfSymbol)
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.3), radius: 20)

                // Illumination bar
                VStack(spacing: 6) {
                    Text("Illumination")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.1))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.yellow.opacity(0.6), .yellow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * moon.illumination, height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int(moon.illumination * 100))%")
                        .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                }
                .padding(.horizontal, DesignTokens.spaceLG)

                // Moon phase cycle strip
                VStack(spacing: 8) {
                    Text("Lunar Cycle")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 0) {
                        ForEach(MoonPhaseData.MoonPhaseType.allPhases, id: \.rawValue) { phase in
                            VStack(spacing: 4) {
                                Image(systemName: phase.sfSymbol)
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(phase == moon.phase ? .yellow : .white.opacity(0.7))

                                if phase == moon.phase {
                                    Circle()
                                        .fill(.yellow)
                                        .frame(width: 4, height: 4)
                                } else {
                                    Circle()
                                        .fill(.clear)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.vertical, DesignTokens.spaceMD)
        } dailyStrip: {
            // 10-day moon phase strip
            ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text(day.date.dayLabel(index: index))
                        .font(.system(size: DesignTokens.smallSize, weight: .medium))
                        .frame(width: 60, alignment: .leading)

                    if let phase = day.moonPhase {
                        Image(systemName: phase.sfSymbol)
                            .font(.system(size: 16))
                            .foregroundStyle(.yellow)
                            .frame(width: 24)

                        Text(phase.rawValue)
                            .font(.system(size: DesignTokens.captionSize))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(Int(day.moonIllumination * 100))%")
                            .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                    } else {
                        Spacer()
                        Text("--")
                            .font(.system(size: DesignTokens.smallSize))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if index < weather.daily.count - 1 {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }
}

// MARK: - Moon Phase Type Extensions

extension MoonPhaseData.MoonPhaseType {
    /// All phases in order for the cycle strip visualization.
    static var allPhases: [MoonPhaseData.MoonPhaseType] {
        [.newMoon, .waxingCrescent, .firstQuarter, .waxingGibbous,
         .fullMoon, .waningGibbous, .lastQuarter, .waningCrescent]
    }
}
