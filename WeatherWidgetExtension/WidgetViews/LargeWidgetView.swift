import SwiftUI
import WidgetKit
import WeatherShared

/// Large widget: phrase is the hero, forecast supports it.
struct LargeWidgetView: View {
    let entry: WeatherWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Weather header row
            HStack(alignment: .center) {
                Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 24))

                Text("\(entry.temperature)°")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.locationName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("H:\(entry.high)° L:\(entry.low)°")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // THE PHRASE — bold, wraps up to 3 lines, auto-shrinks for longest phrases
            Text(entry.phrase)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Divider().overlay(Color.white.opacity(0.15))

            // Hourly strip
            HStack(spacing: 0) {
                ForEach(entry.hourlyPreview) { hour in
                    VStack(spacing: 3) {
                        Text(hour.hour)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: hour.conditionTag.sfSymbol(isDay: hour.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 16))
                        Text("\(hour.temp)°")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().overlay(Color.white.opacity(0.15))

            // Daily forecast
            VStack(spacing: 4) {
                ForEach(entry.dailyPreview) { day in
                    HStack {
                        Text(day.day)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 44, alignment: .leading)

                        // Daily forecast always uses daytime icons (standard weather app convention)
                        Image(systemName: day.conditionTag.sfSymbol(isDay: true))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 15))
                            .frame(width: 22)

                        Spacer()

                        Text("\(day.low)°")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, alignment: .trailing)

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
                                        .frame(height: 4)

                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.accentBlue, .accentRed],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: max(geo.size.width * (1 - leftPct - rightPct), 4),
                                            height: 4
                                        )
                                        .offset(x: geo.size.width * leftPct)
                                }
                            }
                        }
                        .frame(height: 4)

                        Text("\(day.high)°")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}
