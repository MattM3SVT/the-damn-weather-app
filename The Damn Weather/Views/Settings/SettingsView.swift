import SwiftUI
import WeatherShared

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let onPhraseModeChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Phrase Mode
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Explicit Mode")
                                .font(.body)
                            Text("Enable colorful language")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.appState.phraseMode == .explicit },
                            set: { _ in
                                viewModel.toggleExplicitMode()
                                onPhraseModeChanged()
                            }
                        ))
                        .tint(.accentRed)
                    }
                } header: {
                    Text("Phrases")
                }

                // Units
                Section {
                    Picker("Temperature", selection: Binding(
                        get: { viewModel.appState.temperatureUnit },
                        set: { viewModel.appState.saveTemperatureUnit($0) }
                    )) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }

                    Picker("Wind Speed", selection: Binding(
                        get: { viewModel.appState.windSpeedUnit },
                        set: { viewModel.appState.saveWindSpeedUnit($0) }
                    )) {
                        ForEach(WindSpeedUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Picker("Pressure", selection: Binding(
                        get: { viewModel.appState.pressureUnit },
                        set: { viewModel.appState.savePressureUnit($0) }
                    )) {
                        ForEach(PressureUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Picker("Precipitation", selection: Binding(
                        get: { viewModel.appState.precipitationUnit },
                        set: { viewModel.appState.savePrecipitationUnit($0) }
                    )) {
                        ForEach(PrecipitationUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Picker("Distance", selection: Binding(
                        get: { viewModel.appState.distanceUnit },
                        set: { viewModel.appState.saveDistanceUnit($0) }
                    )) {
                        ForEach(DistanceUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } header: {
                    Text("Units")
                }

                // About
                Section {
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("What's New", systemImage: "sparkles")
                    }

                    if let rateURL = URL(string: "https://apps.apple.com/app/id6761637304?action=write-review") {
                        Link(destination: rateURL) {
                            Label("Rate the App", systemImage: "star.fill")
                        }
                    }

                    if let url = URL(string: "https://thedamnweather.com/privacy") {
                        Link(destination: url) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                    }

                    if let url = URL(string: "https://thedamnweather.com/terms") {
                        Link(destination: url) {
                            Label("Terms of Service", systemImage: "doc.text.fill")
                        }
                    }

                    Link(destination: URL(string: "mailto:support@hivewerks.com")!) {
                        Label("Contact Support", systemImage: "envelope.fill")
                    }

                    if let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                        Link(destination: url) {
                            Label("Weather Data by Apple Weather", systemImage: "cloud.fill")
                        }
                    }

                    NavigationLink {
                        DataSourcesView()
                    } label: {
                        Label("About Our Data", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $viewModel.showAgeVerification) {
                AgeVerificationSheet(viewModel: viewModel, onConfirmed: onPhraseModeChanged)
            }
        }
    }
}

/// Simple What's New changelog view
struct WhatsNewView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.3.1")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "aqi.medium", color: .mint, text: "Air quality now actually shows up. A build hiccup silently disabled it in 1.3. Fixed.")
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.3")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "square.and.arrow.up", color: .accentRed, text: "Share the damn weather. Tap the new share icon to send a stylized weather card to friends")
                        ChangelogItem(icon: "aqi.medium", color: .mint, text: "Air quality for US locations. Tap the new AQI card for per-pollutant readings, health guidance, and how today compares to yesterday. Powered by EPA AirNow.")
                        ChangelogItem(icon: "antenna.radiowaves.left.and.right", color: .blue, text: "Observations now cross-checked against NWS and METAR airport data, so the forecast actually knows what's happening outside")
                        ChangelogItem(icon: "widget.small", color: .green, text: "Widgets can now be set to any saved city. Long-press to pick. Existing widgets may need re-adding once.")
                        ChangelogItem(icon: "wrench.and.screwdriver.fill", color: .gray, text: "Bug fixes and polish")
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.2")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "iphone", color: .blue, text: "Now supports iOS 26.0 and later. No forced OS update required.")
                        ChangelogItem(icon: "sparkles", color: .yellow, text: "What's New now shows the full version history")
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.1")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "applelogo", color: .white, text: "Official Apple Weather attribution on every weather screen")
                        ChangelogItem(icon: "star.fill", color: .yellow, text: "\"Rate the App\" button now works in Settings")
                        ChangelogItem(icon: "envelope.fill", color: .blue, text: "Contact Support link added to Settings")
                        ChangelogItem(icon: "chart.xyaxis.line", color: .cyan, text: "Fixed chart \"Now\" label overlapping the section header")
                        ChangelogItem(icon: "hand.raised.fill", color: .green, text: "Privacy manifests for improved App Store compliance")
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.0")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "sun.max.fill", color: .yellow, text: "Real-time weather powered by Apple WeatherKit")
                        ChangelogItem(icon: "quote.opening", color: .accentRed, text: "Sarcastic weather phrases, clean or explicit, your call")
                        ChangelogItem(icon: "chart.xyaxis.line", color: .cyan, text: "Detailed charts for wind, temperature, humidity, and more")
                        ChangelogItem(icon: "location.fill", color: .blue, text: "Save multiple cities and swipe between them")
                        ChangelogItem(icon: "widget.small", color: .green, text: "Home screen widgets with attitude")
                        ChangelogItem(icon: "sunrise.fill", color: .orange, text: "Sun arc, UV index, pressure trends, and 10-day forecasts")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChangelogItem: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
