import SwiftUI
import WeatherShared

/// Severe weather alert banner with expandable details.
struct SevereAlertBanner: View {
    let alerts: [WeatherAlertData]
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
                .background(alertColor(for: alert.severity))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            }
            .sheet(isPresented: $showDetails) {
                AlertDetailsSheet(alerts: alerts)
            }
        }
    }

    private func alertColor(for severity: WeatherAlertData.AlertSeverity) -> Color {
        switch severity {
        case .extreme: return Color(hex: "dc2626")
        case .severe: return Color(hex: "ea580c")
        case .moderate: return Color(hex: "d97706")
        case .minor: return Color(hex: "2563eb")
        case .unknown: return Color(hex: "6b7280")
        }
    }
}

struct AlertDetailsSheet: View {
    let alerts: [WeatherAlertData]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(alerts) { alert in
                    Section {
                        VStack(alignment: .leading, spacing: DesignTokens.spaceSM) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(alert.severity.rawValue.capitalized)
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }

                            Text(alert.headline)
                                .font(.headline)

                            Text(alert.description)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            if let expires = alert.expiresAt {
                                Text("Expires: \(expires.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            Text("Source: \(alert.source)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
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
