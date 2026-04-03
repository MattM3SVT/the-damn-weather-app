import SwiftUI
import WeatherShared

/// Gradient temperature bar for daily forecast rows.
/// Shows a day's temperature range within the context of the overall min/max.
struct TemperatureBar: View {
    let low: Double
    let high: Double
    let overallLow: Double
    let overallHigh: Double
    let unit: TemperatureUnit

    var body: some View {
        GeometryReader { geometry in
            let range = overallHigh - overallLow
            let barWidth = geometry.size.width

            if range > 0 {
                let leftFraction = (low - overallLow) / range
                let rightFraction = (overallHigh - high) / range
                let start = barWidth * leftFraction
                let end = barWidth * (1 - rightFraction)

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(height: 4)

                    // Temperature range bar
                    Capsule()
                        .fill(TemperatureColors.barGradient())
                        .frame(width: max(end - start, 4), height: 4)
                        .offset(x: start)
                }
            } else {
                Capsule()
                    .fill(TemperatureColors.barGradient())
                    .frame(height: 4)
            }
        }
        .frame(height: 4)
    }
}
