import SwiftUI
import WeatherShared

/// 9:16 designed share card — mirrors the in-app HeroSection so a shared image
/// reads as "a poster of the app." Rendered via ImageRenderer at 1080x1920.
struct ShareCardView: View {
    let weather: CurrentWeatherData
    let phrase: String
    let locationName: String
    let dateTimeLabel: String
    let unit: TemperatureUnit
    let isExplicit: Bool
    /// Pre-resolved Apple Weather attribution mark. Nil -> fallback text is rendered.
    /// AsyncImage does not render inside ImageRenderer, so resolution happens upstream.
    let attributionMark: UIImage?

    var body: some View {
        ZStack {
            WeatherGradients.gradient(
                for: weather.conditionTag,
                isDay: weather.isDay,
                colorScheme: .dark
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 24)
                hero
                Spacer(minLength: 40)
                footer
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Top row: wordmark + date/time

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 0) {
                Text("the")
                    .foregroundStyle(.white)
                Text("damn")
                    .foregroundStyle(Color.accentRed)
                Text("weather")
                    .foregroundStyle(.white)
            }
            .font(.system(size: 18, weight: .bold))

            Spacer()

            Text(dateTimeLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    // MARK: - Hero: icon + temp + condition

    private var hero: some View {
        VStack(spacing: 8) {
            WeatherIcon(condition: weather.conditionTag, isDay: weather.isDay, size: 128)

            Text(unit.format(weather.temperature))
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(weather.conditionLabel)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Text("\u{201C}\(phrase)\u{201D}")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 320)
                .padding(.top, 20)
        }
    }

    // MARK: - Footer: location + attribution + wordmark

    private var footer: some View {
        VStack(spacing: 12) {
            Text(locationName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            attributionView

            if isExplicit {
                Text("18+")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
                    )
            }
        }
    }

    @ViewBuilder
    private var attributionView: some View {
        if let attributionMark {
            Image(uiImage: attributionMark)
                .resizable()
                .scaledToFit()
                .frame(height: 14)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "apple.logo")
                Text("Weather")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}
