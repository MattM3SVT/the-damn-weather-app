import Foundation
import SwiftUI
import WeatherShared

@Observable
final class AppState {
    var temperatureUnit: TemperatureUnit = .fahrenheit
    var phraseMode: PhraseMode = .clean
    var explicitConfirmed: Bool = false
    init() {
        loadFromDefaults()
    }

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        if let mode = defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) {
            phraseMode = PhraseMode(rawValue: mode) ?? .clean
        }
        explicitConfirmed = defaults.bool(forKey: AppConstants.UserDefaultsKeys.explicitConfirmed)
        if let unit = defaults.string(forKey: AppConstants.UserDefaultsKeys.temperatureUnit) {
            temperatureUnit = TemperatureUnit(rawValue: unit) ?? .fahrenheit
        }
    }

    func savePhraseMode(_ mode: PhraseMode) {
        phraseMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: AppConstants.UserDefaultsKeys.phraseMode)
    }

    func confirmExplicit() {
        explicitConfirmed = true
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.explicitConfirmed)
    }

    func saveTemperatureUnit(_ unit: TemperatureUnit) {
        temperatureUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: AppConstants.UserDefaultsKeys.temperatureUnit)
    }

}

enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case fahrenheit, celsius

    nonisolated var symbol: String {
        switch self {
        case .fahrenheit: return "°F"
        case .celsius: return "°C"
        }
    }

    nonisolated func format(_ fahrenheit: Double) -> String {
        let value: Double
        switch self {
        case .fahrenheit:
            value = fahrenheit
        case .celsius:
            value = (fahrenheit - 32) * 5 / 9
        }
        return "\(Int(value.rounded()))°"
    }

    nonisolated func formatWithUnit(_ fahrenheit: Double) -> String {
        let value: Double
        switch self {
        case .fahrenheit:
            value = fahrenheit
        case .celsius:
            value = (fahrenheit - 32) * 5 / 9
        }
        return "\(Int(value.rounded()))\(symbol)"
    }

    nonisolated func rawValue(from fahrenheit: Double) -> Double {
        switch self {
        case .fahrenheit: return fahrenheit
        case .celsius: return (fahrenheit - 32) * 5 / 9
        }
    }
}

