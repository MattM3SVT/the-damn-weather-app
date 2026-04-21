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
    /// False when the view was constructed without a daily strip — skips the
    /// "10-Day Overview" GlassCard entirely. Used by metrics WeatherKit doesn't
    /// expose at daily granularity (humidity, dew point, pressure, visibility,
    /// cloud cover) where a fake daily aggregate would be misleading.
    let showsDailyStrip: Bool

    init(
        icon: String,
        title: String,
        currentValue: String,
        subtitle: String,
        description: String,
        accentColor: Color,
        @ViewBuilder chart: @escaping () -> ChartContent,
        @ViewBuilder dailyStrip: @escaping () -> DailyContent
    ) {
        self.icon = icon
        self.title = title
        self.currentValue = currentValue
        self.subtitle = subtitle
        self.description = description
        self.accentColor = accentColor
        self.chart = chart
        self.dailyStrip = dailyStrip
        self.showsDailyStrip = true
    }

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

                        // 24-hour chart. Uses a larger gap below the header than
                        // the other cards so the "Now" pill annotation (~19pt tall,
                        // including its 4pt spacing above the plot top) has room to
                        // render above the chart without crashing into the header.
                        GlassCard {
                            VStack(alignment: .leading, spacing: DesignTokens.spaceLG) {
                                Text("24-Hour Forecast")
                                    .font(.system(size: DesignTokens.captionSize, weight: .medium))
                                    .foregroundStyle(.secondary)

                                chart()
                                    .frame(minHeight: 180)
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

                        // Daily strip — only rendered when the view actually has
                        // per-day data to show. Views for metrics WeatherKit doesn't
                        // expose at daily granularity skip this section.
                        if showsDailyStrip {
                            GlassCard {
                                VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                                    Text("10-Day Overview")
                                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    dailyStrip()
                                }
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

/// Overload for detail views that don't have 10-day data to show.
/// Omit the `dailyStrip:` argument entirely; the "10-Day Overview" section
/// is not rendered.
extension WeatherDetailPage where DailyContent == EmptyView {
    init(
        icon: String,
        title: String,
        currentValue: String,
        subtitle: String,
        description: String,
        accentColor: Color,
        @ViewBuilder chart: @escaping () -> ChartContent
    ) {
        self.icon = icon
        self.title = title
        self.currentValue = currentValue
        self.subtitle = subtitle
        self.description = description
        self.accentColor = accentColor
        self.chart = chart
        self.dailyStrip = { EmptyView() }
        self.showsDailyStrip = false
    }
}

/// Small colored-dot + label chip used as a chart-band key under 24-hour
/// forecast charts. Reused by views whose chart is color-banded
/// (Humidity, DewPoint, Visibility, CloudCover, Pressure).
struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
