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

                    if viewModel.appState.phraseMode == .explicit {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Keep Widgets Clean")
                                    .font(.body)
                                Text("Home and lock screen widgets stay family friendly even in Explicit Mode")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { viewModel.appState.widgetsAlwaysClean },
                                set: { enabled in
                                    viewModel.appState.saveWidgetsAlwaysClean(enabled)
                                    onPhraseModeChanged()
                                }
                            ))
                            .tint(.accentRed)
                        }
                    }
                } header: {
                    Text("Phrases")
                }

                // Notifications
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Morning Forecast")
                                .font(.body)
                            Text("One notification with the day's damn weather")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.morningForecastEnabled)
                            .tint(.accentRed)
                    }

                    if viewModel.morningForecastEnabled {
                        Picker("Delivery Time", selection: $viewModel.morningForecastHour) {
                            ForEach(5...10, id: \.self) { hour in
                                Text("\(hour):00 AM").tag(hour)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Evening Outlook")
                                .font(.body)
                            Text("Tomorrow's damn weather, tonight")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.eveningOutlookEnabled)
                            .tint(.accentRed)
                    }

                    if viewModel.eveningOutlookEnabled {
                        Picker("Delivery Time", selection: $viewModel.eveningOutlookHour) {
                            ForEach(19...22, id: \.self) { hour in
                                Text("\(hour - 12):00 PM").tag(hour)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
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

                #if DEBUG
                Section {
                    Button("Reset review prompt state", role: .destructive) {
                        viewModel.reviewPrompt.resetForDebug()
                    }
                    HStack {
                        Text("Successful fetches")
                        Spacer()
                        Text("\(viewModel.reviewPrompt.successfulFetchCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Has prompted")
                        Spacer()
                        Text(viewModel.reviewPrompt.hasPrompted ? "yes" : "no")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Visible in DEBUG builds only. The OS shows the review sheet on every Simulator/dev call so you can re-test the trigger after resetting state.")
                }
                #endif
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
                    Text("Version 1.4")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "sunrise.fill", color: .orange, text: "Morning Forecast notification. One damn notification with the day's real forecast: rain timing, big temperature swings, and air quality warnings when it matters. Turn it on in Settings.")
                        ChangelogItem(icon: "moon.haze.fill", color: .teal, text: "Evening Outlook notification. Tomorrow's damn weather, tonight, so you can dread it in advance.")
                        ChangelogItem(icon: "quote.opening", color: .accentRed, text: "400 new phrases, including holiday specials. Yes, the app knows when it's Christmas. It has opinions.")
                        ChangelogItem(icon: "lock.iphone", color: .green, text: "Lock screen widgets. The damn weather without unlocking your damn phone.")
                        ChangelogItem(icon: "hand.tap.fill", color: .accentRed, text: "Tap the phrase on any home screen widget for a fresh one. No app required.")
                        ChangelogItem(icon: "mic.fill", color: .purple, text: "Ask Siri: \"What's The Damn Weather\" and hear it with attitude.")
                        ChangelogItem(icon: "moon.stars.fill", color: .indigo, text: "Phrases now respect the clock. Sunshine jokes stay out of midnight and commute jokes stay in the commute, on widgets and everywhere else.")
                        ChangelogItem(icon: "quote.bubble.fill", color: .mint, text: "Explicit Mode users can keep widgets family friendly with the new Keep Widgets Clean setting.")
                        ChangelogItem(icon: "aqi.medium", color: .yellow, text: "Air quality now shows which pollutant is to blame and how fresh the reading is.")
                        ChangelogItem(icon: "wrench.and.screwdriver.fill", color: .gray, text: "Bug fixes. The app left open overnight now notices the sun came up.")
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.3.3")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "quote.opening", color: .accentRed, text: "1,000 new phrases. The damn weather has more to say.")
                        ChangelogItem(icon: "bolt.horizontal.fill", color: .yellow, text: "Saved cities now show real data on launch instead of pretending to load forever")
                        ChangelogItem(icon: "arrow.clockwise", color: .cyan, text: "The pull to refresh spinner no longer hides behind the header bar like it owes someone money")
                        ChangelogItem(icon: "star.fill", color: .yellow, text: "Long time users may get politely asked for a rating after the app earns it")
                        ChangelogItem(icon: "wrench.and.screwdriver.fill", color: .gray, text: "Bug fixes. Less broken than yesterday.")
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version 1.3.2")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        ChangelogItem(icon: "wrench.and.screwdriver.fill", color: .gray, text: "Bug fixes. A few things were being dramatic. They've been talked to.")
                    }
                }
                .padding(.vertical, 8)
            }

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
