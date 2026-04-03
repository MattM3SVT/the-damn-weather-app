import SwiftUI
import WidgetKit
import WeatherShared

/// Large widget: phrase is the hero, forecast supports it.
struct LargeWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Weather header row — compact
            HStack(alignment: .center) {
                Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22))

                Text("\(entry.temperature)°")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(entry.locationName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("H:\(entry.high)° L:\(entry.low)°")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // THE PHRASE — big, bold, full text, no truncation
            Text(entry.phrase)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(4)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Divider().overlay(Color.white.opacity(0.15))

            // Hourly strip — compact
            HStack(spacing: 0) {
                ForEach(entry.hourlyPreview) { hour in
                    VStack(spacing: 2) {
                        Text(hour.hour)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: hour.conditionTag.sfSymbol(isDay: hour.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 12))
                        Text("\(hour.temp)°")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().overlay(Color.white.opacity(0.15))

            // Daily forecast — tighter spacing
            VStack(spacing: 3) {
                ForEach(entry.dailyPreview) { day in
                    HStack {
                        Text(day.day)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 40, alignment: .leading)

                        Image(systemName: day.conditionTag.sfSymbol(isDay: true))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 12))
                            .frame(width: 18)

                        Spacer()

                        Text("\(day.low)°")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 26, alignment: .trailing)

                        GeometryReader { geo in
                            let allLows = entry.dailyPreview.map(\.low)
                            let allHighs = entry.dailyPreview.map(\.high)
                            let minTemp = allLows.min() ?? 0
                            let maxTemp = allHighs.max() ?? 100
                            let range = Double(maxTemp - minTemp)

                            if range > 0 {
                                let leftPct = Double(day.low - minTemp) / range
                                let rightPct = Double(maxTemp - day.high) / range

                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.1))
                                        .frame(height: 3)

                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.accentBlue, .accentRed],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: max(geo.size.width * (1 - leftPct - rightPct), 3),
                                            height: 3
                                        )
                                        .offset(x: geo.size.width * leftPct)
                                }
                            }
                        }
                        .frame(height: 3)

                        Text("\(day.high)°")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}
