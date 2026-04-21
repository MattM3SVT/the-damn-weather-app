import SwiftUI
import WeatherShared

/// A city weather card like Apple Weather's location list,
/// but with the app's signature sarcastic phrase front and center.
struct LocationWeatherCard: View {
    let name: String
    let state: String
    let temperature: String
    let high: String
    let low: String
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let isDay: Bool
    let phrase: String
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: location info + temperature
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if isCurrent {
                        Text("My Location")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(name)
                        .font(.system(size: 22, weight: .bold))
                    if !state.isEmpty {
                        Text(state)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                Text(temperature)
                    .font(.system(size: 48, weight: .thin, design: .rounded))
            }

            Spacer(minLength: 8)

            // The phrase — what makes this app different
            Text(phrase)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            // Bottom row: condition + high/low
            HStack {
                Text(conditionLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("H:\(high)  L:\(low)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(height: 150)
        .background {
            ZStack {
                WeatherGradients.gradient(for: conditionTag, isDay: isDay, colorScheme: .dark)
                // Glass highlight — subtle top-edge glow
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
