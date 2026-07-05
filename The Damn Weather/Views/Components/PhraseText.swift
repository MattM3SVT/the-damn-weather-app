import SwiftUI
import WeatherShared

/// Animated phrase display with tap-to-refresh.
/// The core personality of the app. Long-press to share.
struct PhraseText: View {
    let phrase: String
    var size: CGFloat = DesignTokens.phraseSize
    var isEnabled: Bool = true
    let onTap: () -> Void

    @State private var isVisible = true

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
                ShareLink(item: "\"\(phrase)\" (The Damn Weather)") {
                    Label("Share Phrase", systemImage: "square.and.arrow.up")
                }
            }
            .padding(.horizontal, DesignTokens.spaceMD)
            .accessibilityLabel(phrase)
            .accessibilityHint("Double tap for a new phrase. Touch and hold to share.")
    }
}
