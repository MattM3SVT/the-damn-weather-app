import SwiftUI
import WidgetKit
import WeatherShared

// Lock-screen / accessory widget views. iOS renders these desaturated
// (vibrant mode), so they lean on typography and SF Symbols rather than
// color. The rectangular family is the only one with room for a phrase —
// it reuses `smallPhrase` (≤70 chars), the same budget the small widget uses.

/// One line next to the clock: "72° Partly Cloudy".
struct AccessoryInlineView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        if entry.isPlaceholder {
            Text("The Damn Weather")
        } else {
            ViewThatFits {
                Text("\(entry.temperature)° \(entry.conditionLabel)")
                Text("\(entry.temperature)° \(entry.conditionTag.label)")
                Text("\(entry.temperature)°")
            }
        }
    }
}

/// Small circle: condition icon over the temperature.
struct AccessoryCircularView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.isPlaceholder {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 20))
            } else {
                VStack(spacing: 0) {
                    Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                        .font(.system(size: 14))
                    Text("\(entry.temperature)°")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

/// Rectangular: conditions row + the tiny phrase. The only lock-screen
/// slot with room for attitude. Uses `tinyPhrase` (≤60 chars) — the small
/// widget's 70-char budget visibly truncates in this slot's two lines.
struct AccessoryRectangularView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        if entry.isPlaceholder {
            Text(entry.tinyPhrase)
                .font(.system(size: 12, weight: .semibold))
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                        .font(.system(size: 11))
                    Text("\(entry.temperature)°")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(entry.locationName)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .opacity(0.7)
                }
                // Three lines fit every device: the slot is ≥71.5pt tall and
                // the conditions row + three 11pt lines need ~58pt. At ~23
                // rendered chars per line that's ~69 chars of capacity, so
                // the ≤60-char tinyPhrase renders whole without scaling.
                Text(entry.tinyPhrase)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
