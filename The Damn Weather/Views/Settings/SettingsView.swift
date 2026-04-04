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
                            Text("Explicit Mode (18+)")
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

                    // Rate the App — hidden until actual App Store ID is set
                    if let rateURL = URL(string: "https://apps.apple.com/app/idXXXXXXXXXX"),
                       !rateURL.absoluteString.contains("XXXXXXXXXX") {
                        Link(destination: rateURL) {
                            Label("Rate the App", systemImage: "star.fill")
                        }
                    }

                    Link(destination: URL(string: "https://thedamnweather.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }

                    Link(destination: URL(string: "https://thedamnweather.com/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                    }

                    Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                        Label("Weather Data by Apple Weather", systemImage: "cloud.fill")
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
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
                    Text("Version 1.0")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "sun.max.fill", color: .yellow, text: "Real-time weather powered by Apple WeatherKit")
                        ChangelogItem(icon: "quote.opening", color: .accentRed, text: "Sarcastic weather phrases — clean or explicit, your call")
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
