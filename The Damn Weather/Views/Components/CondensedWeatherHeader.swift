import SwiftUI

/// Compact location + temperature bar that fades in as the hero section collapses.
/// Mirrors Apple Weather's condensed header behavior.
struct CondensedWeatherHeader: View {
    let locationName: String
    let temperature: String
    let conditionLabel: String

    var body: some View {
        HStack(spacing: 6) {
            Text(locationName)
                .font(.system(size: 14, weight: .semibold))
            Text("·")
                .foregroundStyle(.white.opacity(0.5))
            Text(temperature)
                .font(.system(size: 14, weight: .bold))
            Text("·")
                .foregroundStyle(.white.opacity(0.5))
            Text(conditionLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
    }
}
