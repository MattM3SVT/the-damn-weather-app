import SwiftUI

/// Loading skeleton placeholder with shimmer animation.
/// Port of the website's CSS shimmer from animations.css.
struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: DesignTokens.spaceXL) {
            // Hero skeleton
            Circle()
                .frame(width: 80, height: 80)

            RoundedRectangle(cornerRadius: 8)
                .frame(width: 120, height: 60)

            RoundedRectangle(cornerRadius: 8)
                .frame(height: 24)
                .padding(.horizontal, 40)

            RoundedRectangle(cornerRadius: 8)
                .frame(width: 180, height: 16)

            // Stats skeleton
            HStack(spacing: DesignTokens.spaceMD) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .frame(height: 44)
                }
            }
        }
        .foregroundStyle(shimmerGradient)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmerGradient: some ShapeStyle {
        .linearGradient(
            colors: [
                .white.opacity(0.05),
                .white.opacity(0.1),
                .white.opacity(0.05)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
