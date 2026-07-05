import AppIntents
import WeatherShared

/// "Hey Siri, what's The Damn Weather" — speaks the cached conditions plus a
/// phrase. Reads the App Group widget cache instead of fetching so the answer
/// is instant; if nothing recent is cached it says so in-voice. Spoken phrases
/// are ALWAYS clean regardless of the in-app mode — Siri talks out loud in
/// rooms with other people in them.
struct WhatsTheDamnWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "What's the Damn Weather"
    static let description = IntentDescription("Current conditions, with attitude.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let multi = WidgetDataStore.loadMulti()
        let cached = multi[LocationEntity.myLocationID]
            ?? WidgetDataStore.load()
            ?? multi.values.first

        guard let cached,
              Date().timeIntervalSince(cached.updatedAt) <= AppConstants.widgetMaxStaleServeAge,
              let cachedTag = WeatherConditionTag(rawValue: cached.conditionTag) else {
            return .result(dialog: "No damn idea. Open the app so I can check.")
        }

        // Same slot derivation the widget uses so a cache written this
        // afternoon answers with tonight's conditions.
        let now = Date()
        let slot = cached.hourlyPreview
            .filter { $0.date != nil }
            .last { $0.date! <= now }
        let temp = slot.map { $0.temp } ?? Int(cached.temperature.rounded())
        let tag = slot.flatMap { WeatherConditionTag(rawValue: $0.conditionTag) } ?? cachedTag
        let isDay = slot?.isDay ?? cached.isDay
        let tz = cached.timezoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current

        let engine = PhraseEngine(
            defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        )
        let phrase = await engine.selectPhrase(
            conditionTag: tag,
            tempF: Double(temp),
            mode: .clean,
            isDay: isDay,
            localHour: now.localHour(timezone: tz),
            localMonthDay: now.localMonthDay(timezone: tz),
            trackAsSeen: false
        )

        let place = cached.locationName.isEmpty ? "" : " in \(cached.locationName)"
        let condition = tag.label.lowercased()
        return .result(dialog: "It's \(temp) degrees and \(condition)\(place). \(phrase)")
    }
}

struct DamnWeatherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsTheDamnWeatherIntent(),
            phrases: [
                "What's \(.applicationName)",
                "\(.applicationName)",
                "Check \(.applicationName)",
            ],
            shortTitle: "The Damn Weather",
            systemImageName: "cloud.bolt.fill"
        )
    }
}
