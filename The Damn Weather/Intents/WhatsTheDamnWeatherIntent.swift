import AppIntents
import SwiftUI
import WeatherShared

/// "Hey Siri, what's The Damn Weather" — speaks the cached conditions plus a
/// phrase. Reads the App Group widget cache instead of fetching so the answer
/// is instant; if nothing recent is cached it says so in-voice. Spoken phrases
/// are ALWAYS clean regardless of the in-app mode — Siri talks out loud in
/// rooms with other people in them.
struct WhatsTheDamnWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "What's the Damn Weather"
    static let description = IntentDescription("Current conditions, with attitude.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
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
            localIsWeekend: now.isWeekend(timezone: tz),
            trackAsSeen: false
        )

        // The cached name is display-formatted ("Seattle, WA"), but "WA" is
        // for eyes, not ears — Siri spells it out letter by letter. Speak
        // just the city; the card still shows the full "City, ST" form.
        let spokenCity = cached.locationName
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let place = spokenCity.isEmpty ? "" : " in \(spokenCity)"
        let condition = tag.label.lowercased()
        return .result(
            // `full` is spoken in voice-only contexts (AirPods, CarPlay);
            // `supporting` accompanies the visual card, which already shows
            // the temp, condition, and phrase — repeating them read as a bug.
            dialog: IntentDialog(
                full: "It's \(temp) degrees and \(condition)\(place). \(phrase)",
                supporting: "Here's the damn weather."
            ),
            view: WeatherSnippetView(
                temperature: temp,
                conditionTag: tag,
                conditionLabel: tag.label,
                isDay: isDay,
                locationName: cached.locationName,
                phrase: phrase
            )
        )
    }
}

/// Visual card shown in the Siri / Spotlight result surface alongside the
/// spoken dialog. Kept compact: snippet surfaces clip tall content.
private struct WeatherSnippetView: View {
    let temperature: Int
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let isDay: Bool
    let locationName: String
    let phrase: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: conditionTag.sfSymbol(isDay: isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 30))

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(temperature)°")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    if !locationName.isEmpty {
                        Text("\(conditionLabel) · \(locationName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(conditionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text(phrase)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(3)
        }
        .padding()
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
