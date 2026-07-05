import AppIntents
import SwiftUI
import WidgetKit
import WeatherShared

/// Medium widget: phrase dominates. Weather is supporting context.
struct MediumWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)

            // THE PHRASE — big, bold, front and center. Tapping it fires
            // RefreshPhraseIntent for a fresh one without opening the app.
            Button(intent: RefreshPhraseIntent()) {
                Text(entry.phrase)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if !entry.isPlaceholder {
                // Weather context bar at the bottom
                HStack(spacing: 0) {
                    // Current conditions
                    HStack(spacing: 4) {
                        Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 16))
                        Text("\(entry.temperature)°")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }

                    Spacer()

                    // Hi/Lo
                    Text("H:\(entry.high)° L:\(entry.low)°")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    // Location — arrow appears only when showing device GPS location
                    HStack(spacing: 3) {
                        Text(entry.locationName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if entry.isDeviceLocation {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 2) {
                Image(systemName: "apple.logo")
                Text("Weather")
            }
            .font(.system(size: 7))
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.white)
    }
}
