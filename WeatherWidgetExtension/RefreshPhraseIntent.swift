import AppIntents
import WidgetKit
import WeatherShared

/// Fired by tapping the phrase on a home-screen widget. Regenerates the
/// primary + small phrase for every cached location (respecting the current
/// day/night half and phrase mode) and reloads timelines, so the user gets a
/// fresh phrase without opening the app. Weather fields and `updatedAt` are
/// preserved — this is a phrase refresh, not a weather refresh, and bumping
/// the timestamp would lie to the staleness gates.
struct RefreshPhraseIntent: AppIntent {
    static let title: LocalizedStringResource = "New Damn Phrase"
    static let description = IntentDescription("Swap the widget's phrase for a fresh one.")

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let engine = PhraseEngine(defaults: defaults)
        let mode = PhraseMode(
            rawValue: defaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
        ) ?? .clean

        var multi = WidgetDataStore.loadMulti()
        for (id, cached) in multi {
            guard let cachedTag = WeatherConditionTag(rawValue: cached.conditionTag) else { continue }

            // Same derivation the timeline uses: prefer the hourly slot
            // covering now so a tap at 9 PM on an afternoon-written cache
            // regenerates with night phrasing.
            let now = Date()
            let slot = cached.hourlyPreview
                .filter { $0.date != nil }
                .last { $0.date! <= now }
            let isDay = slot?.isDay ?? cached.isDay
            let tag = slot.flatMap { WeatherConditionTag(rawValue: $0.conditionTag) } ?? cachedTag
            let temp = slot.map { Double($0.temp) } ?? cached.temperature
            let tz = cached.timezoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            let localHour = now.localHour(timezone: tz)

            let phrase = await engine.selectPhrase(
                conditionTag: tag,
                tempF: temp,
                mode: mode,
                isDay: isDay,
                localHour: localHour
            )
            let smallPhrase = await engine.selectPhrase(
                conditionTag: tag,
                tempF: temp,
                mode: mode,
                isDay: isDay,
                localHour: localHour,
                maxLength: 70,
                trackAsSeen: false
            )
            let tinyPhrase = await engine.selectPhrase(
                conditionTag: tag,
                tempF: temp,
                mode: mode,
                isDay: isDay,
                localHour: localHour,
                maxLength: AppConstants.accessoryPhraseMaxLength,
                trackAsSeen: false
            )

            multi[id] = CachedWeatherData(
                temperature: cached.temperature,
                conditionTag: cached.conditionTag,
                conditionLabel: cached.conditionLabel,
                isDay: cached.isDay,
                feelsLike: cached.feelsLike,
                high: cached.high,
                low: cached.low,
                locationName: cached.locationName,
                phrase: phrase,
                phraseMode: mode.rawValue,
                updatedAt: cached.updatedAt,
                additionalPhrases: [],
                smallPhrase: smallPhrase,
                tinyPhrase: tinyPhrase,
                hourlyPreview: cached.hourlyPreview,
                dailyPreview: cached.dailyPreview,
                timezoneIdentifier: cached.timezoneIdentifier,
                airQuality: cached.airQuality
            )
        }
        WidgetDataStore.saveMulti(multi)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
