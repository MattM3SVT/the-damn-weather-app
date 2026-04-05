import SwiftUI

/// Minute-by-minute precipitation summary card with attitude.
/// Replaces the old chart with a plain-language description.
struct PrecipitationCard: View {
    let data: [MinutePrecipitationPoint]
    let isExplicit: Bool

    private var summary: PrecipitationSummary {
        PrecipitationSummary(data: data)
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
                HStack(alignment: .top, spacing: DesignTokens.spaceSM) {
                    Image(systemName: summary.icon)
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Text(summary.message(isExplicit: isExplicit))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Precipitation Analysis

private struct PrecipitationSummary {
    let startsInMinutes: Int?
    let endsInMinutes: Int?
    let isRainingNow: Bool
    let peakIntensity: IntensityLevel
    let icon: String

    enum IntensityLevel {
        case light, moderate, heavy

        var label: String {
            switch self {
            case .light: return "light"
            case .moderate: return "moderate"
            case .heavy: return "heavy"
            }
        }
    }

    init(data: [MinutePrecipitationPoint]) {
        guard !data.isEmpty else {
            self.startsInMinutes = nil
            self.endsInMinutes = nil
            self.isRainingNow = false
            self.peakIntensity = .light
            self.icon = "cloud.fill"
            return
        }

        let now = Date()
        let maxIntensity = data.map(\.intensity).max() ?? 0

        if maxIntensity >= 0.3 {
            peakIntensity = .heavy
            icon = "cloud.heavyrain.fill"
        } else if maxIntensity >= 0.1 {
            peakIntensity = .moderate
            icon = "cloud.rain.fill"
        } else {
            peakIntensity = .light
            icon = "cloud.drizzle.fill"
        }

        // Check if it's raining right now (first few minutes have intensity)
        let firstFewMinutes = data.prefix(3)
        isRainingNow = firstFewMinutes.contains { $0.intensity > 0 }

        // Find when rain starts (first minute with intensity > 0)
        if let firstRain = data.first(where: { $0.intensity > 0 }) {
            let minutes = Int(firstRain.time.timeIntervalSince(now) / 60)
            startsInMinutes = max(minutes, 0)
        } else {
            startsInMinutes = nil
        }

        // Find when rain ends (last minute with intensity > 0)
        if let lastRain = data.last(where: { $0.intensity > 0 }) {
            let minutes = Int(lastRain.time.timeIntervalSince(now) / 60)
            endsInMinutes = max(minutes, 0)
        } else {
            endsInMinutes = nil
        }
    }

    func message(isExplicit: Bool) -> String {
        let intensity = peakIntensity.label

        // Scenario 1: Raining now and stops within the hour
        if isRainingNow, let ends = endsInMinutes, ends < 55 {
            let timeStr = minutesDescription(ends)
            return isExplicit
                ? pick([
                    "\(intensity.capitalized) rain happening right now. Should clear up in about \(timeStr). Hang in there, asshole.",
                    "It's raining. \(intensity.capitalized) stuff. Give it \(timeStr) and it'll piss off.",
                    "\(intensity.capitalized) rain. It'll quit its bullshit in about \(timeStr)."
                ])
                : pick([
                    "\(intensity.capitalized) rain right now. Should ease up in about \(timeStr). Patience.",
                    "Currently raining. \(intensity.capitalized) intensity. Give it \(timeStr) and you'll be fine.",
                    "\(intensity.capitalized) rain falling. It'll move on in about \(timeStr)."
                ])
        }

        // Scenario 2: Raining now and continues through the hour
        if isRainingNow {
            return isExplicit
                ? pick([
                    "\(intensity.capitalized) rain and it's not stopping anytime soon. You're stuck with this shit.",
                    "Raining. \(intensity.capitalized). For the whole damn hour at least. Plan accordingly, genius.",
                    "\(intensity.capitalized) rain for the foreseeable future. Umbrella or regret. Your call, dumbass."
                ])
                : pick([
                    "\(intensity.capitalized) rain for at least the next hour. Get comfortable.",
                    "It's raining and it's staying. \(intensity.capitalized) intensity for the foreseeable future.",
                    "\(intensity.capitalized) rain isn't going anywhere. The next hour belongs to it."
                ])
        }

        // Scenario 3: Not raining yet, rain coming
        if let starts = startsInMinutes {
            let timeStr = minutesDescription(starts)
            if let ends = endsInMinutes, ends < 55 {
                let durationStr = minutesDescription(ends - starts)
                return isExplicit
                    ? pick([
                        "\(intensity.capitalized) rain in about \(timeStr). Lasting roughly \(durationStr). Shit timing as always.",
                        "Rain incoming in \(timeStr). \(intensity.capitalized) stuff for about \(durationStr). Fucking wonderful.",
                        "Heads up, dipshit. \(intensity.capitalized) rain hitting in about \(timeStr). Gone in \(durationStr)."
                    ])
                    : pick([
                        "\(intensity.capitalized) rain expected in about \(timeStr). Should last around \(durationStr).",
                        "Rain's coming in \(timeStr). \(intensity.capitalized) intensity, lasting about \(durationStr).",
                        "Expect \(intensity) rain in roughly \(timeStr). It'll pass in about \(durationStr)."
                    ])
            } else {
                return isExplicit
                    ? pick([
                        "\(intensity.capitalized) rain in about \(timeStr). And it's not stopping. Great.",
                        "Rain hitting in \(timeStr). \(intensity.capitalized) and settling in for the long haul. Fuck.",
                        "\(timeStr) until \(intensity) rain arrives and ruins the rest of your night. Shit."
                    ])
                    : pick([
                        "\(intensity.capitalized) rain expected in about \(timeStr). Sticking around a while.",
                        "Rain's on the way. \(intensity.capitalized) intensity arriving in about \(timeStr).",
                        "\(intensity.capitalized) rain incoming in roughly \(timeStr). No end in sight this hour."
                    ])
            }
        }

        // Fallback
        return isExplicit
            ? "Something wet is happening out there. Good luck, asshole."
            : "Precipitation activity detected in the next hour."
    }

    private func minutesDescription(_ minutes: Int) -> String {
        if minutes < 5 { return "a few minutes" }
        if minutes < 10 { return "\(minutes) minutes" }
        // Round to nearest 5
        let rounded = (minutes / 5) * 5
        return "\(rounded) minutes"
    }

    private func pick(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }
}
