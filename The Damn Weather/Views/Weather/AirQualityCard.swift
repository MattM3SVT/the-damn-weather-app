import SwiftUI
import WeatherShared

/// Air quality index display card.
/// Placeholder — WeatherKit AQ data availability varies by region.
struct AirQualityCard: View {
    let cloudCover: Double
    let visibility: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                HStack {
                    Image(systemName: "aqi.medium")
                        .foregroundStyle(.secondary)
                    Text("Air Quality")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(qualityLabel)
                    .font(.system(size: DesignTokens.bodySize, weight: .semibold))

                // Simple quality indicator bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.1))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(qualityColor)
                            .frame(width: geometry.size.width * qualityFraction, height: 4)
                    }
                }
                .frame(height: 4)

                Text(visibility.visibilityDescription + " visibility")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Estimate based on visibility (rough proxy when actual AQI unavailable)
    private var qualityFraction: Double {
        min(visibility / 15.0, 1.0)
    }

    private var qualityLabel: String {
        switch visibility {
        case ..<1: return "Poor"
        case ..<3: return "Fair"
        case ..<6: return "Moderate"
        case ..<10: return "Good"
        default: return "Excellent"
        }
    }

    private var qualityColor: Color {
        switch visibility {
        case ..<1: return .red
        case ..<3: return .orange
        case ..<6: return .yellow
        case ..<10: return .green
        default: return Color(hex: "2ecc71")
        }
    }
}
