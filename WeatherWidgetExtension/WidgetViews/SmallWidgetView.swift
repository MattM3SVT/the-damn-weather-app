import SwiftUI
import WidgetKit
import WeatherShared

/// Small widget: the phrase IS the widget. Temp is minimal context.
struct SmallWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Minimal weather — just temp and icon inline
            HStack(spacing: 3) {
                Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                Text("\(entry.temperature)°")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 0)

            // THE PHRASE — fill as much space as possible
            Text(entry.phrase)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(6)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}
