import SwiftUI

/// Moon phase visualization card.
struct MoonPhaseCard: View {
    let moonPhase: MoonPhaseData

    var body: some View {
        GlassCard {
            VStack(spacing: DesignTokens.spaceSM) {
                HStack {
                    Image(systemName: moonPhase.phase.sfSymbol)
                        .foregroundStyle(.secondary)
                    Text("Moon")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Moon visualization
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.05))
                        .frame(width: 60, height: 60)

                    Image(systemName: moonSymbol)
                        .font(.system(size: 40))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.yellow.opacity(0.8))
                }

                Text(moonPhase.phase.rawValue)
                    .font(.system(size: DesignTokens.smallSize, weight: .semibold))
            }
        }
    }

    private var moonSymbol: String {
        switch moonPhase.phase {
        case .newMoon: return "moonphase.new.moon"
        case .waxingCrescent: return "moonphase.waxing.crescent"
        case .firstQuarter: return "moonphase.first.quarter"
        case .waxingGibbous: return "moonphase.waxing.gibbous"
        case .fullMoon: return "moonphase.full.moon"
        case .waningGibbous: return "moonphase.waning.gibbous"
        case .lastQuarter: return "moonphase.last.quarter"
        case .waningCrescent: return "moonphase.waning.crescent"
        }
    }
}
