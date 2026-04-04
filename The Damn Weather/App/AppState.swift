import Foundation
import SwiftUI
import WeatherShared

@Observable
final class AppState {
    var temperatureUnit: TemperatureUnit = .fahrenheit
    var windSpeedUnit: WindSpeedUnit = .mph
    var pressureUnit: PressureUnit = .hPa
    var precipitationUnit: PrecipitationUnit = .inches
    var distanceUnit: DistanceUnit = .miles
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
        if let unit = defaults.string(forKey: AppConstants.UserDefaultsKeys.windSpeedUnit) {
            windSpeedUnit = WindSpeedUnit(rawValue: unit) ?? .mph
        }
        if let unit = defaults.string(forKey: AppConstants.UserDefaultsKeys.pressureUnit) {
            pressureUnit = PressureUnit(rawValue: unit) ?? .hPa
        }
        if let unit = defaults.string(forKey: AppConstants.UserDefaultsKeys.precipitationUnit) {
            precipitationUnit = PrecipitationUnit(rawValue: unit) ?? .inches
        }
        if let unit = defaults.string(forKey: AppConstants.UserDefaultsKeys.distanceUnit) {
            distanceUnit = DistanceUnit(rawValue: unit) ?? .miles
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

    func saveWindSpeedUnit(_ unit: WindSpeedUnit) {
        windSpeedUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: AppConstants.UserDefaultsKeys.windSpeedUnit)
    }

    func savePressureUnit(_ unit: PressureUnit) {
        pressureUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: AppConstants.UserDefaultsKeys.pressureUnit)
    }

    func savePrecipitationUnit(_ unit: PrecipitationUnit) {
        precipitationUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: AppConstants.UserDefaultsKeys.precipitationUnit)
    }

    func saveDistanceUnit(_ unit: DistanceUnit) {
        distanceUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: AppConstants.UserDefaultsKeys.distanceUnit)
    }
}

// MARK: - Temperature Unit

enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case fahrenheit, celsius

    nonisolated var symbol: String {
        switch self {
        case .fahrenheit: return "°F"
        case .celsius: return "°C"
        }
    }

    nonisolated var label: String {
        switch self {
        case .fahrenheit: return "Fahrenheit"
        case .celsius: return "Celsius"
        }
    }

    /// Convert from Fahrenheit (internal storage) to this unit
    nonisolated func convert(_ fahrenheit: Double) -> Double {
        switch self {
        case .fahrenheit: return fahrenheit
        case .celsius: return (fahrenheit - 32) * 5 / 9
        }
    }

    nonisolated func format(_ fahrenheit: Double) -> String {
        "\(Int(convert(fahrenheit).rounded()))°"
    }

    /// Short format for chart axis labels (just number + °)
    nonisolated func formatShort(_ convertedValue: Double) -> String {
        "\(Int(convertedValue.rounded()))°"
    }

    nonisolated func formatWithUnit(_ fahrenheit: Double) -> String {
        "\(Int(convert(fahrenheit).rounded()))\(symbol)"
    }

    nonisolated func rawValue(from fahrenheit: Double) -> Double {
        switch self {
        case .fahrenheit: return fahrenheit
        case .celsius: return (fahrenheit - 32) * 5 / 9
        }
    }
}

// MARK: - Wind Speed Unit

enum WindSpeedUnit: String, CaseIterable, Sendable {
    case mph, kmh, knots, ms

    nonisolated var label: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "km/h"
        case .knots: return "knots"
        case .ms: return "m/s"
        }
    }

    /// Convert from mph (internal storage) to this unit
    nonisolated func convert(_ mph: Double) -> Double {
        switch self {
        case .mph: return mph
        case .kmh: return mph * 1.60934
        case .knots: return mph * 0.868976
        case .ms: return mph * 0.44704
        }
    }

    nonisolated func format(_ mph: Double) -> String {
        let value = convert(mph)
        return "\(Int(value.rounded())) \(label)"
    }
}

// MARK: - Pressure Unit

enum PressureUnit: String, CaseIterable, Sendable {
    case hPa, inHg, mmHg

    nonisolated var label: String {
        switch self {
        case .hPa: return "hPa"
        case .inHg: return "inHg"
        case .mmHg: return "mmHg"
        }
    }

    /// Convert from hPa (internal storage) to this unit
    nonisolated func convert(_ hPa: Double) -> Double {
        switch self {
        case .hPa: return hPa
        case .inHg: return hPa * 0.02953
        case .mmHg: return hPa * 0.75006
        }
    }

    nonisolated func format(_ hPa: Double) -> String {
        let value = convert(hPa)
        switch self {
        case .hPa: return "\(Int(value.rounded())) hPa"
        case .inHg: return String(format: "%.2f inHg", value)
        case .mmHg: return "\(Int(value.rounded())) mmHg"
        }
    }
}

// MARK: - Precipitation Unit

enum PrecipitationUnit: String, CaseIterable, Sendable {
    case inches, mm

    nonisolated var label: String {
        switch self {
        case .inches: return "in"
        case .mm: return "mm"
        }
    }

    /// Convert from inches (internal storage) to this unit
    nonisolated func convert(_ inches: Double) -> Double {
        switch self {
        case .inches: return inches
        case .mm: return inches * 25.4
        }
    }

    nonisolated func format(_ inches: Double) -> String {
        let value = convert(inches)
        switch self {
        case .inches:
            if value < 0.01 { return "0 in" }
            return String(format: "%.2f in", value)
        case .mm:
            if value < 0.25 { return "0 mm" }
            return String(format: "%.1f mm", value)
        }
    }

    nonisolated func formatRate(_ inchesPerHour: Double) -> String {
        let value = convert(inchesPerHour)
        switch self {
        case .inches:
            if value < 0.01 { return "0 in/hr" }
            return String(format: "%.2f in/hr", value)
        case .mm:
            if value < 0.25 { return "0 mm/hr" }
            return String(format: "%.1f mm/hr", value)
        }
    }
}

// MARK: - Distance Unit

enum DistanceUnit: String, CaseIterable, Sendable {
    case miles, km

    nonisolated var label: String {
        switch self {
        case .miles: return "mi"
        case .km: return "km"
        }
    }

    /// Convert from miles (internal storage) to this unit
    nonisolated func convert(_ miles: Double) -> Double {
        switch self {
        case .miles: return miles
        case .km: return miles * 1.60934
        }
    }

    nonisolated func format(_ miles: Double) -> String {
        let value = convert(miles)
        if value >= 10 {
            return "\(Int(value.rounded())) \(label)"
        }
        return String(format: "%.1f \(label)", value)
    }
}
