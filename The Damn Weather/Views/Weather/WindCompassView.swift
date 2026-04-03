import SwiftUI
import WeatherShared

/// Wind direction compass visualization.
struct WindCompassView: View {
    let direction: Double  // degrees
    let speed: Double      // mph
    let gusts: Double      // mph

    var body: some View {
        GlassCard {
            VStack(spacing: DesignTokens.spaceSM) {
                HStack {
                    Image(systemName: "wind")
                        .foregroundStyle(.secondary)
                    Text("Wind")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ZStack {
                    // Compass ring
                    Circle()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 80, height: 80)

                    // Cardinal directions
                    ForEach(["N", "E", "S", "W"], id: \.self) { dir in
                        Text(dir)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .offset(compassOffset(for: dir))
                    }

                    // Wind direction arrow
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentRed)
                        .rotationEffect(.degrees(direction))
                }
                .frame(width: 100, height: 100)

                VStack(spacing: 2) {
                    Text("\(speed.windSpeedString) \(direction.compassDirection)")
                        .font(.system(size: DesignTokens.smallSize, weight: .semibold))

                    if gusts > speed {
                        Text("Gusts \(gusts.windSpeedString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func compassOffset(for direction: String) -> CGSize {
        let distance: CGFloat = 48
        switch direction {
        case "N": return CGSize(width: 0, height: -distance)
        case "S": return CGSize(width: 0, height: distance)
        case "E": return CGSize(width: distance, height: 0)
        case "W": return CGSize(width: -distance, height: 0)
        default: return .zero
        }
    }
}
