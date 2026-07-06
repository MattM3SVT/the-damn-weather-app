import SwiftUI
import WeatherKit
import WeatherShared

/// Everything the share card needs beyond the phrase itself. Provided by
/// HeroSection so the long-press share produces the exact same stylized
/// card as the header share button.
struct PhraseShareContext {
    let weather: CurrentWeatherData
    let locationName: String
    let timezone: TimeZone
    let unit: TemperatureUnit
    let isExplicit: Bool
    let attribution: WeatherAttribution?
}

/// Animated phrase display with tap-to-refresh.
/// The core personality of the app. Long-press to share the weather card.
struct PhraseText: View {
    let phrase: String
    var size: CGFloat = DesignTokens.phraseSize
    var isEnabled: Bool = true
    let onTap: () -> Void
    var shareContext: PhraseShareContext? = nil

    @State private var isVisible = true
    @State private var shareImage: Image?
    @State private var attributionMark: UIImage?

    /// Re-render triggers, mirroring ShareButton's identity key.
    private var renderIdentity: String {
        guard let ctx = shareContext else { return "none" }
        let markKey = attributionMark == nil ? "none" : "mark"
        return "\(ctx.weather.temperature)-\(ctx.weather.conditionTag.rawValue)-\(ctx.weather.isDay)-\(phrase)-\(ctx.locationName)-\(ctx.isExplicit)-\(ctx.unit.rawValue)-\(markKey)"
    }

    var body: some View {
        Text(phrase)
            .font(.system(size: size, weight: .semibold, design: .default))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
            .contentTransition(.opacity)
            .onTapGesture {
                guard isEnabled else { return }
                HapticsService.lightTap()
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onTap()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible = true
                    }
                }
            }
            .contextMenu {
                if let shareImage, let ctx = shareContext {
                    // The same pre-rendered card the header button shares.
                    ShareLink(
                        item: shareImage,
                        subject: Text("The Damn Weather"),
                        preview: SharePreview(
                            "\(ctx.unit.format(ctx.weather.temperature)) in \(ctx.locationName)",
                            image: shareImage
                        )
                    ) {
                        Label("Share Phrase", systemImage: "square.and.arrow.up")
                    }
                } else {
                    // Context not provided or card still rendering — plain
                    // text beats a dead menu item.
                    ShareLink(item: "\"\(phrase)\" (The Damn Weather)") {
                        Label("Share Phrase", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task(id: renderIdentity) {
                await regenerateCard()
            }
            .task(id: shareContext?.attribution?.combinedMarkDarkURL) {
                guard let ctx = shareContext else { return }
                attributionMark = await ShareCardRenderer.resolveAttributionMark(from: ctx.attribution)
            }
            .padding(.horizontal, DesignTokens.spaceMD)
            .accessibilityLabel(phrase)
            .accessibilityHint("Double tap for a new phrase. Touch and hold to share.")
    }

    @MainActor
    private func regenerateCard() async {
        guard let ctx = shareContext else { return }
        let card = ShareCardView(
            weather: ctx.weather,
            phrase: phrase,
            locationName: ctx.locationName,
            dateTimeLabel: ShareCardRenderer.dateTimeLabel(timezone: ctx.timezone),
            unit: ctx.unit,
            isExplicit: ctx.isExplicit,
            attributionMark: attributionMark
        )
        if let uiImage = ShareCardRenderer.render(card) {
            shareImage = Image(uiImage: uiImage)
        }
    }
}
