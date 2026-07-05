import Foundation
import WeatherShared

@Observable
final class SettingsViewModel {
    let appState: AppState
    let reviewPrompt: ReviewPromptCoordinator

    var showAgeVerification = false

    var morningForecastEnabled: Bool {
        didSet {
            UserDefaults.standard.set(morningForecastEnabled, forKey: AppConstants.UserDefaultsKeys.morningForecastEnabled)
            Task { await MorningForecastService.shared.updateSchedule() }
        }
    }
    var morningForecastHour: Int {
        didSet {
            UserDefaults.standard.set(morningForecastHour, forKey: AppConstants.UserDefaultsKeys.morningForecastTime)
            Task { await MorningForecastService.shared.updateSchedule() }
        }
    }

    init(appState: AppState, reviewPrompt: ReviewPromptCoordinator) {
        self.appState = appState
        self.reviewPrompt = reviewPrompt
        let defaults = UserDefaults.standard
        morningForecastEnabled = defaults.bool(forKey: AppConstants.UserDefaultsKeys.morningForecastEnabled)
        morningForecastHour = defaults.object(forKey: AppConstants.UserDefaultsKeys.morningForecastTime) as? Int ?? 7
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
}
