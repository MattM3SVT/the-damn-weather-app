import SwiftUI

/// Minute-by-minute precipitation summary card.
/// Shows clear, informative text about what to expect in the next hour.
struct PrecipitationCard: View {
    let data: [MinutePrecipitationPoint]

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

                    Text(summary.message)
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

    enum IntensityLevel: String {
        case light = "Light"
        case moderate = "Moderate"
        case heavy = "Heavy"
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

    var message: String {
        // Scenario 1: Raining now and stops within the hour
        if isRainingNow, let ends = endsInMinutes, ends < 55 {
            return "\(peakIntensity.rawValue) rain right now. Expected to stop in \(minutesDescription(ends))."
        }

        // Scenario 2: Raining now and continues through the hour
        if isRainingNow {
            return "\(peakIntensity.rawValue) rain continuing for at least the next hour."
        }

        // Scenario 3: Not raining yet, rain coming and ending within the hour
        if let starts = startsInMinutes {
            if let ends = endsInMinutes, ends < 55 {
                let duration = ends - starts
                return "\(peakIntensity.rawValue) rain expected in \(minutesDescription(starts)), lasting about \(minutesDescription(duration))."
            } else {
                return "\(peakIntensity.rawValue) rain expected in \(minutesDescription(starts)), continuing through the hour."
            }
        }

        // Fallback
        return "Precipitation expected in the next hour."
    }

    private func minutesDescription(_ minutes: Int) -> String {
        if minutes < 5 { return "a few minutes" }
        if minutes < 10 { return "\(minutes) minutes" }
        let rounded = (minutes / 5) * 5
        return "\(rounded) minutes"
    }
}
