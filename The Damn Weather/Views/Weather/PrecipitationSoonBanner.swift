import SwiftUI
import WeatherShared

/// "Rain starting in about 12 minutes" callout, built from WeatherKit's
/// minute-by-minute forecast. Shown only when it is NOT currently
/// precipitating but precipitation is expected within the next hour — the
/// one moment where minute data changes what the user does next.
struct PrecipitationSoonBanner: View {
    let minutes: Int
    let isSnow: Bool

    private var message: String {
        let kind = isSnow ? "Snow" : "Rain"
        let tail = isSnow ? "Bundle up." : "You've been warned."
        if minutes <= 2 {
            return "\(kind) starting any minute now. \(tail)"
        }
        return "\(kind) starting in about \(minutes) minutes. \(tail)"
    }

    var body: some View {
        HStack(spacing: DesignTokens.spaceSM) {
            Image(systemName: isSnow ? "snowflake" : "umbrella.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.accentBlue)

            Text(message)
                .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignTokens.spaceMD)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    /// Minutes until precipitation starts, or nil when it's already
    /// precipitating, nothing meaningful is coming inside the window, or
    /// there's no minute data (non-US locations, partial snapshots).
    ///
    /// Thresholds: ≥50% probability with nonzero intensity marks a "real"
    /// start; the first minute of the series decides "already precipitating".
    static func minutesUntilStart(
        _ data: [MinutePrecipitationPoint],
        now: Date = Date()
    ) -> Int? {
        let upcoming = data
            .filter { $0.time >= now.addingTimeInterval(-60) }
            .sorted { $0.time < $1.time }
        guard let current = upcoming.first else { return nil }

        func isPrecipitating(_ p: MinutePrecipitationPoint) -> Bool {
            p.intensity > 0.002 && p.probability >= 50
        }

        guard !isPrecipitating(current) else { return nil }
        guard let start = upcoming.first(where: isPrecipitating) else { return nil }

        let minutes = Int((start.time.timeIntervalSince(now) / 60).rounded())
        guard (0...60).contains(minutes) else { return nil }
        return max(minutes, 1)
    }
}
