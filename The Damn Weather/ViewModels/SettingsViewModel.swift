import Foundation
import WeatherShared

@Observable
final class SettingsViewModel {
    let appState: AppState
    private let notificationService = NotificationService()
    let reviewPrompt: ReviewPromptCoordinator

    var showAgeVerification = false
    var morningForecastEnabled: Bool {
        didSet {
            UserDefaults.standard.set(morningForecastEnabled, forKey: AppConstants.UserDefaultsKeys.morningForecastEnabled)
            Task { await updateMorningForecast() }
        }
    }
    var morningForecastHour: Int {
        didSet {
            UserDefaults.standard.set(morningForecastHour, forKey: AppConstants.UserDefaultsKeys.morningForecastTime)
            Task { await updateMorningForecast() }
        }
    }
    var severeWeatherAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(severeWeatherAlertsEnabled, forKey: AppConstants.UserDefaultsKeys.severeWeatherAlertsEnabled)
        }
    }

    init(appState: AppState, reviewPrompt: ReviewPromptCoordinator) {
        self.appState = appState
        self.reviewPrompt = reviewPrompt
        let defaults = UserDefaults.standard
        morningForecastEnabled = defaults.bool(forKey: AppConstants.UserDefaultsKeys.morningForecastEnabled)
        morningForecastHour = defaults.object(forKey: AppConstants.UserDefaultsKeys.morningForecastTime) as? Int ?? 7
        severeWeatherAlertsEnabled = defaults.object(forKey: AppConstants.UserDefaultsKeys.severeWeatherAlertsEnabled) as? Bool ?? true
    }

    func toggleExplicitMode() {
        if appState.phraseMode == .explicit {
            appState.savePhraseMode(.clean)
        } else {
            if appState.explicitConfirmed {
                appState.savePhraseMode(.explicit)
            } else {
                showAgeVerification = true
            }
        }
    }

    func confirmAge() {
        appState.confirmExplicit()
        appState.savePhraseMode(.explicit)
        showAgeVerification = false
        HapticsService.rigidTap()
    }

    func cancelAge() {
        showAgeVerification = false
    }

    private func updateMorningForecast() async {
        if morningForecastEnabled {
            let granted = await notificationService.requestPermission()
            if granted {
                await notificationService.scheduleMorningForecast(
                    hour: morningForecastHour,
                    body: "Check the app for your damn forecast."
                )
            }
        } else {
            await notificationService.cancelMorningForecast()
        }
    }
}
