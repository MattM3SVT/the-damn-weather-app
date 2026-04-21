import SwiftUI
import WeatherKit
import WeatherShared

/// Header share button. Pre-renders the share card as soon as weather data
/// is available so the tap-to-present latency is effectively zero.
///
/// Uses `ShareLink(item: Image)` — the built-in SwiftUI.Image Transferable.
/// This is the only item form that makes AirDrop reliable on both the
/// regular AirDrop path and the share sheet's top-row quick-pick suggestions.
/// Filename at the AirDrop destination is iOS's default (not customizable
/// without sacrificing quick-pick AirDrop reliability).
struct ShareButton: View {
    let weather: CurrentWeatherData
    let phrase: String
    let locationName: String
    let timezone: TimeZone
    let unit: TemperatureUnit
    let isExplicit: Bool
    let attribution: WeatherAttribution?

    @State private var shareImage: Image?
    @State private var attributionMark: UIImage?
    @State private var tapCount = 0
    @State private var presentedCount = 0

    private var dateTimeLabel: String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMd h:mm a")
        return f.string(from: Date())
    }

    private var identity: String {
        let markKey = attributionMark == nil ? "none" : "mark"
        return "\(weather.temperature)-\(weather.conditionTag.rawValue)-\(weather.isDay)-\(phrase)-\(locationName)-\(isExplicit)-\(unit.rawValue)-\(markKey)"
    }

    var body: some View {
        Group {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    subject: Text("The Damn Weather"),
                    preview: SharePreview(
                        "\(unit.format(weather.temperature)) in \(locationName)",
                        image: shareImage
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    tapCount &+= 1
                    DispatchQueue.main.async { presentedCount &+= 1 }
                })
                .accessibilityLabel("Share weather")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: tapCount)
        .sensoryFeedback(.success, trigger: presentedCount)
        .task(id: identity) {
            await regenerate()
        }
        .task(id: attribution?.combinedMarkDarkURL) {
            attributionMark = await ShareCardRenderer.resolveAttributionMark(from: attribution)
        }
    }

    @MainActor
    private func regenerate() async {
        let card = ShareCardView(
            weather: weather,
            phrase: phrase,
            locationName: locationName,
            dateTimeLabel: dateTimeLabel,
            unit: unit,
            isExplicit: isExplicit,
            attributionMark: attributionMark
        )
        if let uiImage = ShareCardRenderer.render(card) {
            shareImage = Image(uiImage: uiImage)
        }
    }
}
