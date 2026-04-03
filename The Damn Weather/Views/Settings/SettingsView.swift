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

                // Appearance
                Section {
                    Picker("Temperature", selection: Binding(
                        get: { viewModel.appState.temperatureUnit },
                        set: { viewModel.appState.saveTemperatureUnit($0) }
                    )) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                // Notifications
                Section {
                    Toggle("Morning Forecast", isOn: $viewModel.morningForecastEnabled)
                        .tint(.accentRed)

                    if viewModel.morningForecastEnabled {
                        Picker("Time", selection: $viewModel.morningForecastHour) {
                            ForEach(5..<12, id: \.self) { hour in
                                Text("\(hour):00 AM").tag(hour)
                            }
                        }
                    }

                    Toggle("Severe Weather Alerts", isOn: $viewModel.severeWeatherAlertsEnabled)
                        .tint(.accentRed)
                } header: {
                    Text("Notifications")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                    Link("Weather Data by Apple Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
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
