import SwiftUI
import Charts
import WeatherShared

/// Reusable template for Apple Weather-style detail pages.
/// Provides a consistent layout: header, 24-hour chart, description, and daily strip.
struct WeatherDetailPage<ChartContent: View, DailyContent: View>: View {
    let icon: String
    let title: String
    let currentValue: String
    let subtitle: String
    let description: String
    let accentColor: Color
    @ViewBuilder let chart: () -> ChartContent
    @ViewBuilder let dailyStrip: () -> DailyContent

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.weatherBgDark
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignTokens.spaceLG) {
                        // Current value hero
                        VStack(spacing: DesignTokens.spaceSM) {
                            Image(systemName: icon)
                                .font(.system(size: 36))
                                .foregroundStyle(accentColor)

                            Text(currentValue)
                                .font(.system(size: 48, weight: .black, design: .rounded))

                            Text(subtitle)
                                .font(.system(size: DesignTokens.bodySize, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, DesignTokens.spaceMD)

                        // 24-hour chart
                        GlassCard {
                            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                                Text("24-Hour Forecast")
                                    .font(.system(size: DesignTokens.captionSize, weight: .medium))
                                    .foregroundStyle(.secondary)

                                chart()
                                    .frame(height: 180)
                            }
                        }

                        // Description / guidance card
                        if !description.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                                    Text("What This Means")
                                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    Text(description)
                                        .font(.system(size: DesignTokens.bodySize))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }

                        // Daily strip
                        GlassCard {
                            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                                Text("10-Day Overview")
                                    .font(.system(size: DesignTokens.captionSize, weight: .medium))
                                    .foregroundStyle(.secondary)

                                dailyStrip()
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.spaceMD)
                    .padding(.bottom, DesignTokens.space2XL)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }
}

/// Reusable daily row for detail page strips
struct DailyStripRow: View {
    let dayLabel: String
    let value: String
    let icon: String?
    let iconColor: Color

    var body: some View {
        HStack {
            Text(dayLabel)
                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                .frame(width: 60, alignment: .leading)

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
            }

            Spacer()

            Text(value)
                .font(.system(size: DesignTokens.smallSize, weight: .semibold))
        }
    }
}
