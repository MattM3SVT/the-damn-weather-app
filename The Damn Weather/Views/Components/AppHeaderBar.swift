import SwiftUI
import WeatherKit
import WeatherShared

/// App header bar matching the website layout:
/// Logo (left) | Search bar (center) | 18+ toggle + Share + Settings gear (right)
struct AppHeaderBar: View {
    let appState: AppState
    let settingsVM: SettingsViewModel
    let locationName: String
    let onSearchTap: () -> Void
    let onLogoTap: () -> Void
    let onPhraseModeChanged: () -> Void
    var showBackground: Bool = true
    var showSearchBar: Bool = true

    /// Inputs for the Share button. All nil => button is hidden (no weather loaded yet).
    var shareWeather: CurrentWeatherData? = nil
    var sharePhrase: String = ""
    var shareLocationName: String = ""
    var shareTimezone: TimeZone = .current
    var shareAttribution: WeatherAttribution? = nil

    @State private var showAgeVerification = false
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 10) {
            // Logo — tappable for saved locations
            Button(action: onLogoTap) {
                HStack(spacing: 0) {
                    Text("the")
                        .foregroundStyle(.white)
                    Text("damn")
                        .foregroundStyle(Color.accentRed)
                    Text("weather")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 16, weight: .bold))
                .fixedSize()
            }
            .accessibilityLabel("The Damn Weather — tap for saved locations")

            if showSearchBar {
                // Search bar — fills remaining space
                Button(action: onSearchTap) {
                    HStack(spacing: 6) {
                        if !locationName.isEmpty {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(locationName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        } else {
                            Text("Enter zip code or city...")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .layoutPriority(-1)
            } else {
                Spacer()
            }

            // 18+ toggle
            Toggle(isOn: Binding(
                get: { appState.phraseMode == .explicit },
                set: { _ in
                    if appState.phraseMode == .explicit {
                        appState.savePhraseMode(.clean)
                        onPhraseModeChanged()
                    } else if appState.explicitConfirmed {
                        appState.savePhraseMode(.explicit)
                        onPhraseModeChanged()
                    } else {
                        showAgeVerification = true
                    }
                    HapticsService.lightTap()
                }
            )) {
                Text("Explicit")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .toggleStyle(.switch)
            .tint(Color.accentRed)
            .fixedSize()

            // Share button — appears once weather data is available
            if let shareWeather, !sharePhrase.isEmpty, !shareLocationName.isEmpty {
                ShareButton(
                    weather: shareWeather,
                    phrase: sharePhrase,
                    locationName: shareLocationName,
                    timezone: shareTimezone,
                    unit: appState.temperatureUnit,
                    isExplicit: appState.phraseMode == .explicit,
                    attribution: shareAttribution
                )
            }

            // Settings gear
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, DesignTokens.spaceMD)
        .padding(.vertical, 6)
        .background {
            if showBackground {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .sheet(isPresented: $showAgeVerification) {
            AgeVerificationSheet(viewModel: settingsVM, onConfirmed: onPhraseModeChanged)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: settingsVM, onPhraseModeChanged: onPhraseModeChanged)
        }
    }
}
