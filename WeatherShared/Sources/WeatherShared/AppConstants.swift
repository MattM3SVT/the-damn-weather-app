import Foundation

public enum AppConstants {
    public static let appGroupID = "group.DamnWeather.The-Damn-Weather"
    public static let weatherCacheTTL: TimeInterval = 15 * 60  // 15 minutes
    public static let maxSeenPhrases = 300
    public static let windOverrideThreshold: Double = 25.0  // mph

    // Observation cross-check (NWS + METAR supplemental current-condition correction)
    public static let observationCacheTTL: TimeInterval = 30 * 60        // 30 min
    public static let stationResolutionCacheTTL: TimeInterval = 24 * 3600  // 24h
    public static let noNWSCoverageCacheTTL: TimeInterval = 24 * 3600     // 24h
    public static let nwsMinInterRequestInterval: TimeInterval = 1.1      // seconds
    public static let observationMaxStaleness: TimeInterval = 2 * 3600    // 2h
    public static let crossCheckHTTPTimeout: TimeInterval = 10            // seconds
    public static let nwsSupportEmail = "support@hivewerks.com"

    // Cross-check confidence thresholds. Used by applyConsensusOverride to
    // block a ground-station override when WK's own cloud-cover reading
    // strongly confirms its base tag. Protects against microclimate mismatch
    // (the nearest ASOS station can be 10+ miles from the user).
    public static let wkHighCloudConfidenceThreshold: Double = 80  // ≥ 80% cloud cover → trust WK "cloudy"
    public static let wkLowCloudConfidenceThreshold: Double = 20   // ≤ 20% cloud cover → trust WK "clear"

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
        /// True when the widget should use the device's current GPS location.
        /// False when the widget should use the saved lat/lon (user pinned a city in-app).
        public static let lastLocationIsCurrentDevice = "lastLocationIsCurrentDevice"
        public static let cachedConditionLabel = "cachedConditionLabel"
        public static let cachedIsDay = "cachedIsDay"
        public static let cachedFeelsLike = "cachedFeelsLike"
        public static let cachedHigh = "cachedHigh"
        public static let cachedLow = "cachedLow"
        public static let currentPhrase = "currentPhrase"
    }
}
