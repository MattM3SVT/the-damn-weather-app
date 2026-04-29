import Foundation

public enum AppConstants {
    public static let appGroupID = "group.DamnWeather.The-Damn-Weather"
    public static let weatherCacheTTL: TimeInterval = 15 * 60  // 15 minutes
    /// Upper bound on how old a cache entry can be while still being served by
    /// PATH 1.5 (live-fetch failed, fall back to cached). Beyond this the
    /// widget renders a placeholder asking the user to open the app rather
    /// than displaying obviously-stale labels.
    public static let widgetMaxStaleServeAge: TimeInterval = 6 * 3600  // 6 hours
    public static let maxSeenPhrases = 300
    public static let windOverrideThreshold: Double = 25.0  // mph

    // Observation cross-check (NWS + METAR supplemental current-condition correction)
    public static let observationCacheTTL: TimeInterval = 30 * 60        // 30 min
    public static let stationResolutionCacheTTL: TimeInterval = 24 * 3600  // 24h
    public static let noNWSCoverageCacheTTL: TimeInterval = 24 * 3600     // 24h
    public static let nwsMinInterRequestInterval: TimeInterval = 1.1      // seconds
    public static let observationMaxStaleness: TimeInterval = 2 * 3600    // 2h
    public static let crossCheckHTTPTimeout: TimeInterval = 10            // seconds
    public static let crossCheckOuterTimeout: TimeInterval = 12           // whole-fetch budget
    public static let crossCheckCacheMaxEntries = 200                     // LRU cap per dict
    /// How long the most recent NWS+METAR consensus stays useable as a
    /// sticky fallback after the next refetch fails (network blip, NWS 5xx,
    /// METAR fetch timeout, or the outer-timeout firing). When a fresh
    /// fetch would otherwise return `.empty` and suppress the sky-cover
    /// override, we'd rather use a slightly older but still valid consensus
    /// than flip the displayed condition to WeatherKit's raw tag.
    public static let crossCheckStickyMaxAge: TimeInterval = 2 * 3600     // 2h
    public static let nwsSupportEmail = "support@hivewerks.com"

    // Air quality (AirNow / EPA) supplemental data
    public static let airQualityCacheTTL: TimeInterval = 30 * 60          // 30 min
    // Negative cache is deliberately short. AirNow returns an empty body for
    // both "permanently outside coverage" (non-US) and "temporarily no
    // nearby monitor reporting" (US rural, monitor maintenance, data gap).
    // We can't tell them apart, so 4h balances not hammering AirNow with
    // not blocking a real recovery for a full day.
    public static let airQualityNoCoverageTTL: TimeInterval = 4 * 3600    // 4h
    public static let airNowHTTPTimeout: TimeInterval = 15                // per request (cold-start safe)
    public static let airNowOuterTimeout: TimeInterval = 18               // whole-fetch budget
    // Gates concurrent AirNow requests within the process. Prefetch of 7
    // saved locations fires 14 requests (current + historical per location).
    // A 0.2s inter-request interval caps peak throughput at ~300/min, well
    // under AirNow's 500/hr limit while keeping the worst-case prefetch wait
    // under 3s.
    public static let airNowMinInterRequestInterval: TimeInterval = 0.2
    public static let airQualityCacheMaxEntries = 200                     // LRU cap
    /// How long a cached AQI reading is allowed to keep showing as a sticky
    /// fallback when the next fresh fetch fails (transient 5xx, timeout,
    /// network jitter). After this window we'd rather hide the card than
    /// show data that's misleading. 2h matches AirNow's hourly update
    /// cadence so the worst-case staleness is two reporting cycles.
    public static let airQualityStickyMaxAge: TimeInterval = 2 * 3600     // 2h

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
        public static let morningForecastEnabled = "morningForecastEnabled"
        public static let morningForecastTime = "morningForecastTime"
        public static let severeWeatherAlertsEnabled = "severeWeatherAlertsEnabled"
        public static let windSpeedUnit = "windSpeedUnit"
        public static let pressureUnit = "pressureUnit"
        public static let precipitationUnit = "precipitationUnit"
        public static let distanceUnit = "distanceUnit"
        public static let lastShownClean = "lastShownPhrase_clean"
        public static let lastShownExplicit = "lastShownPhrase_explicit"
        // Review-prompt coordinator state. `firstLaunchDate` is set once on
        // first run and never overwritten so the days-since-install gate is
        // anchored to a real install. `successfulFetchCount` increments only
        // on non-partial weather loads (a "wow moment" — the user just saw
        // the app deliver value). `hasPromptedForReview` flips true the
        // first (and only) time we call `requestReview()` so the prompt is
        // never shown twice, even if Apple's 365-day budget would allow it.
        public static let reviewFirstLaunchDate = "reviewPrompt_firstLaunchDate"
        public static let reviewSuccessfulFetchCount = "reviewPrompt_successfulFetchCount"
        public static let reviewHasPrompted = "reviewPrompt_hasPrompted"
        // NOTE: `lastLocation*` and `cached*` UserDefaults keys were removed in
        // the per-widget-configurable-location rewrite. Each widget now carries
        // its own location via `WeatherWidgetIntent`, and cached weather lives
        // in `widget-weather-multi.json` keyed by `LocationEntity.id`.
    }
}
