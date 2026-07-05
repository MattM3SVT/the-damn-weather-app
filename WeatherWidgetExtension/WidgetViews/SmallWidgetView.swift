import AppIntents
import SwiftUI
import WidgetKit
import WeatherShared

/// Small widget: the phrase IS the widget. Temp is minimal context.
struct SmallWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.isPlaceholder {
                // No weather data yet — just show the prompt
                Spacer()
                Text(entry.phrase)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(5)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                // City label — Apple Weather-style. Arrow indicator ONLY appears
                // when the widget is rendering the device's current GPS location
                // (entry.isDeviceLocation). For user-pinned saved cities, just
                // the name is shown. Hidden entirely when there's no real name.
                if !entry.locationName.isEmpty && entry.locationName != "Unknown" {
                    HStack(spacing: 3) {
                        Text(entry.locationName)
                            .font(.system(size: 12, weight: .medium))
                        if entry.isDeviceLocation {
                            Image(systemName: "location.fill")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                // Temperature and condition icon — prominent
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.temperature)°")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 20))
                    Spacer()
                }

                // THE PHRASE — bold, fills remaining space, uses short variant for small widget.
                // Font intentionally lower (17pt) with aggressive minimumScaleFactor so full
                // phrases up to ~70 chars fit in the ~40pt vertical budget that's left after
                // the city row, temp row, and attribution. PhraseEngine additionally hard-caps
                // maxLength and truncates at word boundaries as a safety net.
                Button(intent: RefreshPhraseIntent()) {
                    Text(entry.smallPhrase)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(4)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 2) {
                    Image(systemName: "apple.logo")
                    Text("Weather")
                }
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(.white)
    }
}
