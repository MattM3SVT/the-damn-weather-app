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

                // THE PHRASE — bold, fills remaining space, uses short variant for small widget
                Text(entry.smallPhrase)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(5)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .foregroundStyle(.white)
    }
}
