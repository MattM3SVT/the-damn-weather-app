import SwiftUI
import WeatherShared

/// Apple Weather-style air quality detail sheet. Layout (top to bottom):
///   1. Hero (icon matched to severity, AQI number, category label,
///      reporting-area subline when available)
///   2. Gauge card (category-aligned gradient with dot + "vs yesterday" line)
///   3. Health Information card
///   4. Primary Pollutant card
///   5. Pollutant Details table
///   6. EPA AirNow attribution footer
///
/// Built from `GlassCard` primitives directly rather than reusing
/// `WeatherDetailPage` because the section order and content differ
/// substantially from the weather-detail template (no 24h chart, no daily
/// strip).
struct AirQualityDetailView: View {
    let data: AirQualityData

    @Environment(\.dismiss) private var dismiss

    private var accentColor: Color { data.category.accentColor }

    /// "25 minutes ago" formatter for the observation timestamp. Relative
    /// phrasing sidesteps the location-vs-device timezone question entirely.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.weatherBgDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignTokens.spaceLG) {
                        hero
                        gaugeCard
                        healthCard
                        primaryPollutantCard
                        pollutantsCard
                        attributionFooter
                    }
                    .padding(.horizontal, DesignTokens.spaceMD)
                    .padding(.bottom, DesignTokens.space2XL)
                }
            }
            .navigationTitle("Air Quality")
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

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: DesignTokens.spaceSM) {
            Image(systemName: data.category.sfSymbol)
                .font(.system(size: 36))
                .foregroundStyle(accentColor)

            Text("\(data.aqi)")
                .font(.system(size: 48, weight: .black, design: .rounded))

            Text(data.category.label)
                .font(.system(size: DesignTokens.bodySize, weight: .medium))
                .foregroundStyle(.secondary)

            // Which pollutant is driving the number and how fresh it is.
            // Surprising values (fireworks smoke, wildfire plumes) read as
            // app bugs without this line.
            Text("\(data.primaryPollutant.shortSymbol) · Updated \(Self.relativeFormatter.localizedString(for: data.observedAt, relativeTo: Date()))")
                .font(.system(size: DesignTokens.captionSize))
                .foregroundStyle(.white.opacity(0.5))

            if let area = data.reportingArea, !area.isEmpty {
                Text(area)
                    .font(.system(size: DesignTokens.captionSize))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .padding(.top, DesignTokens.spaceMD)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Air Quality Index \(data.aqi), \(data.category.label)")
    }

    // MARK: - Gauge card

    private var gaugeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignTokens.spaceLG) {
                HStack {
                    Text(data.category.label)
                        .font(.system(size: DesignTokens.sectionTitleSize, weight: .semibold))
                    Spacer()
                    Text("Scale: United States (AQI)")
                        .font(.system(size: DesignTokens.captionSize))
                        .foregroundStyle(.secondary)
                }

                Text(yesterdayComparisonCopy)
                    .font(.system(size: DesignTokens.bodySize))
                    .foregroundStyle(.white.opacity(0.85))

                AQIGauge(value: data.aqi)
                    .frame(height: 8)
                    .accessibilityElement()
                    .accessibilityLabel("AQI gauge")
                    .accessibilityValue("\(data.aqi), \(data.category.label)")
            }
        }
    }

    /// "Air quality index is N, which is (similar to / higher than / lower
    /// than) yesterday's worst." AirNow's free historical endpoint is a daily
    /// aggregate, so we compare against yesterday's peak value across the day.
    /// Falls back to a plain statement when yesterday's data isn't available.
    private var yesterdayComparisonCopy: String {
        guard let yesterday = data.yesterdayPeakAQI else {
            return "Air quality index is \(data.aqi)."
        }
        let delta = data.aqi - yesterday
        let relation: String
        if abs(delta) <= 5 {
            relation = "similar to"
        } else if delta > 0 {
            relation = "higher than"
        } else {
            relation = "lower than"
        }
        return "Air quality index is \(data.aqi), which is \(relation) yesterday's worst."
    }

    // MARK: - Health info

    private var healthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                Text("Health Information")
                    .font(.system(size: DesignTokens.captionSize, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(data.category.healthInfo)
                    .font(.system(size: DesignTokens.bodySize))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: - Primary pollutant

    private var primaryPollutantCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                Text("Primary Pollutant")
                    .font(.system(size: DesignTokens.captionSize, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(data.primaryPollutant.displayName) (\(data.primaryPollutant.shortSymbol))")
                    .font(.system(size: DesignTokens.bodySize, weight: .semibold))

                Text(data.primaryPollutant.contextExplanation)
                    .font(.system(size: DesignTokens.bodySize))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: - Pollutant table

    private var pollutantsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                HStack {
                    Text("Pollutant Details")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("AQI")
                        .font(.system(size: DesignTokens.captionSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(data.pollutants.enumerated()), id: \.element.id) { index, reading in
                    PollutantRow(reading: reading)
                    if index < data.pollutants.count - 1 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
        }
    }

    // MARK: - Attribution

    private var attributionFooter: some View {
        VStack(spacing: 4) {
            if let url = URL(string: "https://www.airnow.gov/") {
                Link(destination: url) {
                    Text("Air Quality data provided by U.S. EPA AirNow")
                        .font(.system(size: DesignTokens.captionSize))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Air Quality data provided by U.S. EPA AirNow")
                    .font(.system(size: DesignTokens.captionSize))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, DesignTokens.spaceSM)
    }
}

// MARK: - AQI Gauge

/// Horizontal rainbow gauge showing where the current AQI sits on the 0-500
/// scale. Gradient stops are placed at EPA category midpoints so the color at
/// any given dot position matches the category for that AQI value. Apple
/// Weather uses a similar category-aligned gradient rather than a simple
/// evenly-distributed rainbow.
struct AQIGauge: View {
    let value: Int

    private var fraction: Double {
        min(1.0, max(0.0, Double(value) / 500.0))
    }

    /// Stops are placed at the percentage midpoint of each EPA category on
    /// the 0-500 scale:
    ///   Good (0-50)                 center 25  → 5%
    ///   Moderate (51-100)           center 75  → 15%
    ///   Unhealthy-Sensitive (101-150) center 125 → 25%
    ///   Unhealthy (151-200)         center 175 → 35%
    ///   Very Unhealthy (201-300)    center 250 → 50%
    ///   Hazardous (301-500)         center 400 → 80%
    private static let stops: [Gradient.Stop] = [
        .init(color: .green,  location: 0.05),
        .init(color: .yellow, location: 0.15),
        .init(color: .orange, location: 0.25),
        .init(color: .red,    location: 0.35),
        .init(color: .purple, location: 0.50),
        .init(color: Color(red: 0.5, green: 0.0, blue: 0.12), location: 0.80)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: Self.stops),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                let dotSize = geo.size.height + 4
                Circle()
                    .fill(.white)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: max(0, geo.size.width * fraction - dotSize / 2))
            }
        }
    }
}

// MARK: - Pollutant row

/// One row of the pollutant details table. Short symbol on the left (matching
/// Apple's CO / NO₂ / O₃ styling), full name in the middle, per-pollutant AQI
/// on the right. AirNow's free CSV endpoint doesn't return raw concentrations,
/// so the trailing value is the AQI number for that pollutant. The column
/// header "AQI" in the parent view clarifies the unit.
struct PollutantRow: View {
    let reading: PollutantReading

    var body: some View {
        HStack(spacing: DesignTokens.spaceMD) {
            Text(reading.pollutant.shortSymbol)
                .font(.system(size: DesignTokens.smallSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(reading.pollutant.displayName)
                .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                .lineLimit(2)

            Spacer()

            Text("\(reading.aqi)")
                .font(.system(size: DesignTokens.smallSize))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reading.pollutant.displayName), AQI \(reading.aqi)")
    }
}
