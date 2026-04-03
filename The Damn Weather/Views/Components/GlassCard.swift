import SwiftUI

/// Frosted glass card component used for detail cards and forecast sections.
struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignTokens.spaceMD)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    // Subtle top-edge highlight for glass depth
                    LinearGradient(
                        colors: [.white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

/// Wider variant with less padding for list-style content
struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [.white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}
