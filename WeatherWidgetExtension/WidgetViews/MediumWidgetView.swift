import SwiftUI
import WidgetKit
import WeatherShared

/// Medium widget: phrase dominates. Weather is supporting context.
struct MediumWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)

            // THE PHRASE — big, bold, front and center
            Text(entry.phrase)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

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

                    // Location
                    Text(entry.locationName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
    }
}
