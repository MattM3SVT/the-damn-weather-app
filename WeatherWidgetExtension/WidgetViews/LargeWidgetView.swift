import AppIntents
import SwiftUI
import WidgetKit
import WeatherShared

/// Large widget: phrase is the hero, forecast supports it.
/// Uses GeometryReader to scale proportionally across iPhone and iPad.
struct LargeWidgetView: View {
    let entry: WeatherWidgetEntry

    /// Hourly slot label, computed at render time from the slot's date so that
    /// a slightly-stale cache shows accurate hours instead of the labels that
    /// were frozen when the cache was written. Falls back to the cached `hour`
    /// string for legacy cache records that pre-date the `date` field.
    private func label(for hour: WeatherWidgetEntry.HourlyWidgetPoint) -> String {
        guard let slotDate = hour.date else { return hour.hour }
        let calendar = Calendar.current
        let nowHourStart = calendar.dateInterval(of: .hour, for: Date())?.start
        let slotHourStart = calendar.dateInterval(of: .hour, for: slotDate)?.start
        if let nowHourStart, let slotHourStart, nowHourStart == slotHourStart {
            return "Now"
        }
        // Strip the space "9 PM" → "9PM" to match the widget's existing
        // tight-spaced layout (the strip has six slots in a narrow row).
        return slotDate.hourLabel(timezone: entry.displayTimezone)
            .replacingOccurrences(of: " ", with: "")
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(1.3, max(0.95, geo.size.width / 338))

            if entry.isPlaceholder {
                // No weather data yet — centered prompt
                VStack {
                    Spacer()
                    Text(entry.phrase)
                        .font(.system(size: 20 * scale, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    // Weather header row
                    HStack(alignment: .center) {
                        Image(systemName: entry.conditionTag.sfSymbol(isDay: entry.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 24 * scale))

                        Text("\(entry.temperature)°")
                            .font(.system(size: 30 * scale, weight: .bold, design: .rounded))

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2 * scale) {
                            HStack(spacing: 3 * scale) {
                                Text(entry.locationName)
                                    .font(.system(size: 11 * scale, weight: .medium))
                                if entry.isDeviceLocation {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 8 * scale, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white.opacity(0.6))
                            Text("H:\(entry.high)° L:\(entry.low)°")
                                .font(.system(size: 11 * scale, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Spacer(minLength: 0)

                    // THE PHRASE — bold, wraps up to 3 lines, auto-shrinks for
                    // longest phrases. Tapping it fires RefreshPhraseIntent.
                    Button(intent: RefreshPhraseIntent()) {
                        Text(entry.phrase)
                            .font(.system(size: 17 * scale, weight: .bold))
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Divider().overlay(Color.white.opacity(0.15))

                    // Hourly strip
                    HStack(spacing: 0) {
                        ForEach(entry.hourlyPreview) { hour in
                            VStack(spacing: 3 * scale) {
                                Text(label(for: hour))
                                    .font(.system(size: 11 * scale))
                                    .foregroundStyle(.white.opacity(0.6))
                                Image(systemName: hour.conditionTag.sfSymbol(isDay: hour.isDay))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 16 * scale))
                                Text("\(hour.temp)°")
                                    .font(.system(size: 13 * scale, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.15))

                    // Daily forecast
                    VStack(spacing: 4 * scale) {
                        ForEach(entry.dailyPreview) { day in
                            HStack {
                                Text(day.day)
                                    .font(.system(size: 13 * scale, weight: .medium))
                                    .frame(width: 44 * scale, alignment: .leading)

                                // Daily forecast always uses daytime icons (standard weather app convention)
                                Image(systemName: day.conditionTag.sfSymbol(isDay: true))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 15 * scale))
                                    .frame(width: 22 * scale)

                                Spacer()

                                Text("\(day.low)°")
                                    .font(.system(size: 12 * scale))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 28 * scale, alignment: .trailing)

                                GeometryReader { barGeo in
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
                                                .frame(height: 4 * scale)

                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.accentBlue, .accentRed],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(
                                                    width: max(barGeo.size.width * (1 - leftPct - rightPct), 4),
                                                    height: 4 * scale
                                                )
                                                .offset(x: barGeo.size.width * leftPct)
                                        }
                                    }
                                }
                                .frame(height: 4 * scale)

                                Text("\(day.high)°")
                                    .font(.system(size: 12 * scale, weight: .semibold))
                                    .frame(width: 28 * scale, alignment: .trailing)
                            }
                        }
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "apple.logo")
                        Text("Weather")
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.white)
            }
        }
    }
}
