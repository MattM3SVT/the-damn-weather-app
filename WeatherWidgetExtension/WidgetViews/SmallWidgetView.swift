import SwiftUI
import WidgetKit
import WeatherShared

/// Small widget: the phrase IS the widget. Temp is minimal context.
struct SmallWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            Spacer(minLength: 0)

            // THE PHRASE — bold, fills remaining space, auto-shrinks for long text
            Text(entry.phrase)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }
}
