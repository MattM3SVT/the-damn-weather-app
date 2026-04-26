import SwiftUI
import WeatherShared

/// Severe weather alert banner with expandable details.
struct SevereAlertBanner: View {
    let alerts: [WeatherAlertData]
    let timezone: TimeZone
    @State private var showDetails = false

    private var primaryAlert: WeatherAlertData? {
        alerts.first
    }

    var body: some View {
        if let alert = primaryAlert {
            Button {
                HapticsService.warning()
                showDetails = true
            } label: {
                HStack(spacing: DesignTokens.spaceSM) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.headline)
                            .font(.system(size: DesignTokens.smallSize, weight: .semibold))
                            .lineLimit(1)

                        if alerts.count > 1 {
                            Text("+\(alerts.count - 1) more alert\(alerts.count > 2 ? "s" : "")")
                                .font(.caption)
                                .opacity(0.8)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding(DesignTokens.spaceMD)
                .background(alert.severity.bannerColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            }
            .sheet(isPresented: $showDetails) {
                AlertDetailsSheet(alerts: alerts, timezone: timezone)
            }
        }
    }
}

extension WeatherAlertData.AlertSeverity {
    /// Color used in the collapsed banner row. Saturation tuned to read
    /// against the dark app background.
    var bannerColor: Color {
        switch self {
        case .extreme: return Color(hex: "dc2626")
        case .severe: return Color(hex: "ea580c")
        case .moderate: return Color(hex: "d97706")
        case .minor: return Color(hex: "2563eb")
        case .unknown: return Color(hex: "6b7280")
        }
    }

    /// Color used for the severity label / icon inside the details sheet —
    /// brighter than the banner because the sheet's surface is darker.
    var accentColor: Color {
        switch self {
        case .extreme: return Color(hex: "f87171")
        case .severe:  return Color(hex: "fb923c")
        case .moderate: return Color(hex: "fbbf24")
        case .minor:   return Color(hex: "60a5fa")
        case .unknown: return Color(hex: "9ca3af")
        }
    }
}

struct AlertDetailsSheet: View {
    let alerts: [WeatherAlertData]
    let timezone: TimeZone
    @Environment(\.dismiss) private var dismiss

    /// Format alert times in the location's timezone so users viewing a
    /// remote city see them in that city's local clock.
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.spaceMD) {
                    ForEach(alerts) { alert in
                        AlertCard(alert: alert, formattedDate: formattedDate)
                    }
                }
                .padding(.horizontal, DesignTokens.spaceMD)
                .padding(.vertical, DesignTokens.spaceSM)
            }
            .navigationTitle("Weather Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Single alert card. Renders parsed NWS sections natively when available;
/// falls back to embedding the WeatherKit details page when not.
private struct AlertCard: View {
    let alert: WeatherAlertData
    let formattedDate: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spaceMD) {
            header
            if let areaDesc = alert.areaDesc, !areaDesc.isEmpty {
                Text(areaDesc.collapsingWhitespace)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            descriptionContent

            if let instruction = alert.instruction, !instruction.isEmpty {
                InstructionCallout(text: instruction.normalizedNWSText)
            }

            metadataFooter
        }
        .padding(DesignTokens.spaceMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(alert.severity.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spaceXS) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(alert.severity.accentColor)
                    .font(.caption)
                Text(alert.severity.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(alert.severity.accentColor)
                    .tracking(0.8)
            }
            Text(alert.headline)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if let description = alert.description, !description.isEmpty {
            let sections = description.parsedNWSSections
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.spaceMD) {
                    ForEach(sections.indices, id: \.self) { idx in
                        NWSSectionView(section: sections[idx])
                    }
                }
            } else {
                Text(description.normalizedNWSText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let url = alert.detailsURL {
            // Non-US or unmatched alert — embed the issuer's web page so the
            // user reads the full details without leaving the app.
            AlertWebView(url: url)
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        }
    }

    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onset = alert.onset, let ends = alert.ends {
                metadataRow(icon: "clock", label: "In effect", value: "\(formattedDate(onset)) – \(formattedDate(ends))")
            } else if let ends = alert.ends {
                metadataRow(icon: "clock", label: "Ends", value: formattedDate(ends))
            }
            if let expires = alert.expiresAt {
                metadataRow(icon: "hourglass", label: "Alert expires", value: formattedDate(expires))
            }
            metadataRow(icon: "antenna.radiowaves.left.and.right", label: "Source", value: alert.source)
        }
        .padding(.top, DesignTokens.spaceXS)
    }

    @ViewBuilder
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 12)
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One parsed `* HEADER...body` block, rendered with a small uppercase label
/// above the body text.
private struct NWSSectionView: View {
    let section: NWSAlertSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.header)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.0)
            Text(section.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tinted callout for the NWS "instruction" field — the recommended actions
/// the user should take. Visually distinct from the descriptive sections.
private struct InstructionCallout: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("WHAT TO DO")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                    .tracking(1.0)
            }
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.spaceMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - NWS text parsing

struct NWSAlertSection: Sendable {
    let header: String  // "WHAT", "WHERE", "WHEN", "IMPACTS", "ADDITIONAL DETAILS"
    let body: String    // Cleaned-up body text with paragraph breaks preserved
}

extension String {
    /// Collapse runs of whitespace (incl. embedded newlines) into single
    /// spaces. Used for fields like `areaDesc` that read as a single line.
    var collapsingWhitespace: String {
        self
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Normalize NWS bulletin text. NWS feeds preserve teletype-style hard
    /// line breaks at ~70 chars, which look ugly inside SwiftUI's word
    /// wrapping ("frost\nformation."). Fold single newlines into spaces;
    /// preserve double newlines as paragraph breaks.
    var normalizedNWSText: String {
        let placeholder = "\u{0001}\u{0001}"
        return self
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\n", with: placeholder)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: placeholder, with: "\n\n")
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: " \n\n", with: "\n\n")
            .replacingOccurrences(of: "\n\n ", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses NWS bulletin sections like:
    ///
    ///   * WHAT...Temperatures as low as 32 degrees…
    ///   * WHERE...Southern Hood Canal…
    ///   * WHEN...From 11 PM this evening…
    ///   * IMPACTS...Frost could harm…
    ///
    /// Returns `[]` when the text doesn't follow this format — caller
    /// should fall back to rendering the raw normalized text.
    var parsedNWSSections: [NWSAlertSection] {
        let normalized = self.normalizedNWSText
        // Match "* HEADER..." where HEADER is a sequence of uppercase letters
        // and spaces (e.g., "WHAT", "ADDITIONAL DETAILS"). The "..." may have
        // any number of dots in the wild.
        let pattern = #"\*\s+([A-Z][A-Z\s]*?)\.{2,}\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [] }

        var sections: [NWSAlertSection] = []
        for (i, match) in matches.enumerated() {
            let header = nsText
                .substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            let body = nsText
                .substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(NWSAlertSection(header: header, body: body))
        }
        return sections
    }
}
