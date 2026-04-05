import Foundation

public enum AppConstants {
    public static let appGroupID = "group.DamnWeather.The-Damn-Weather"
    public static let weatherCacheTTL: TimeInterval = 15 * 60  // 15 minutes
    public static let maxSeenPhrases = 300
    public static let windOverrideThreshold: Double = 25.0  // mph

    public enum UserDefaultsKeys {
        public static let phraseMode = "phraseMode"
        public static let explicitConfirmed = "explicitConfirmed"
        public static let seenPhrasesClean = "seenPhrases_clean"
        public static let seenPhrasesExplicit = "seenPhrases_explicit"
        public static let temperatureUnit = "temperatureUnit"
        public static let theme = "theme"
        public static let lastLocationLat = "lastLocationLat"
        public static let lastLocationLon = "lastLocationLon"
        public static let lastLocationName = "lastLocationName"
        public static let morningForecastEnabled = "morningForecastEnabled"
        public static let morningForecastTime = "morningForecastTime"
        public static let severeWeatherAlertsEnabled = "severeWeatherAlertsEnabled"
        public static let windSpeedUnit = "windSpeedUnit"
        public static let pressureUnit = "pressureUnit"
        public static let precipitationUnit = "precipitationUnit"
        public static let distanceUnit = "distanceUnit"
        public static let lastShownClean = "lastShownPhrase_clean"
        public static let lastShownExplicit = "lastShownPhrase_explicit"
        // Cached weather data for widget fallback
        public static let cachedTemperature = "cachedTemperature"
        public static let cachedConditionTag = "cachedConditionTag"
        public static let cachedConditionLabel = "cachedConditionLabel"
        public static let cachedIsDay = "cachedIsDay"
        public static let cachedFeelsLike = "cachedFeelsLike"
        public static let cachedHigh = "cachedHigh"
        public static let cachedLow = "cachedLow"
    }
}
