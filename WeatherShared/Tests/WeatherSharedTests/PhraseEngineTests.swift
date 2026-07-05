import Foundation
import Testing
@testable import WeatherShared

/// Tests run against the real shipped phrase JSON so gating regressions in
/// either the engine or the data fail loudly.
@Suite("PhraseEngine gating")
struct PhraseEngineTests {

    /// Fresh, isolated defaults per engine so tests never touch real state.
    /// The defaults instance is created and handed off in one expression so
    /// Swift 6 region isolation allows sending it into the actor.
    private func makeEngine() -> PhraseEngine {
        let suite = "WeatherSharedTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        return PhraseEngine(defaults: UserDefaults(suiteName: suite)!)
    }

    /// Load the raw phrase list so a selected (rendered) phrase can be mapped
    /// back to its metadata.
    private func loadPhrases(_ name: String) throws -> [Phrase] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode([Phrase].self, from: Data(contentsOf: url))
    }

    @Test("dayOnly phrases never fire at night, nightOnly never during day")
    func dayNightGating() async throws {
        let engine = makeEngine()
        let phrases = try loadPhrases("phrases-clean")
        let tempF = 60.0
        let byRendered = Dictionary(
            phrases.map { ($0.rendered(tempF: tempF), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        for isDay in [true, false] {
            for _ in 0..<150 {
                let text = await engine.selectPhrase(
                    conditionTag: .clear, tempF: tempF, mode: .clean, isDay: isDay
                )
                let phrase = try #require(byRendered[text], "selected phrase not found in pool: \(text)")
                if isDay {
                    #expect(!phrase.nightOnly, "nightOnly phrase during day: \(text)")
                } else {
                    #expect(!phrase.dayOnly, "dayOnly phrase at night: \(text)")
                }
            }
        }
    }

    @Test("no back-to-back repeats")
    func noConsecutiveRepeats() async {
        let engine = makeEngine()
        var previous = ""
        for _ in 0..<50 {
            let text = await engine.selectPhrase(conditionTag: .rain, tempF: 50, mode: .clean, isDay: true)
            #expect(text != previous)
            previous = text
        }
    }

    @Test("maxLength is a hard cap")
    func maxLengthHardCap() async {
        let engine = makeEngine()
        for _ in 0..<100 {
            let text = await engine.selectPhrase(
                conditionTag: .thunderstorm, tempF: 70, mode: .clean, isDay: true, maxLength: 70
            )
            #expect(text.count <= 70, "over budget (\(text.count)): \(text)")
        }
    }

    @Test("every condition tag yields a phrase at extreme temps")
    func noEmptyPools() async {
        let engine = makeEngine()
        let guardPrefix = "It's "
        for tag in [WeatherConditionTag.clear, .partlyCloudy, .cloudy, .fog, .drizzle,
                    .rain, .heavyRain, .freezingRain, .snow, .heavySnow, .thunderstorm, .wind] {
            for temp in [-20.0, 55.0, 115.0] {
                for isDay in [true, false] {
                    let text = await engine.selectPhrase(conditionTag: tag, tempF: temp, mode: .clean, isDay: isDay)
                    #expect(!text.isEmpty)
                    // The deterministic guard string means the pool was empty.
                    #expect(!text.hasPrefix(guardPrefix) || !text.hasSuffix("That's the weather."),
                            "fallback guard fired for \(tag) \(temp) day=\(isDay)")
                }
            }
        }
    }

    @Test("truncated() cuts at word boundaries with ellipsis")
    func wordBoundaryTruncation() {
        let long = "Partly cloudy night. 58 degrees. The moon keeps disappearing like your motivation."
        let cut = PhraseFormatting.truncated(long, to: 72)
        #expect(cut.count <= 72)
        #expect(cut.hasSuffix("…"))
        // Never mid-word: dropping the ellipsis leaves a whole-word prefix.
        let prefix = String(cut.dropLast())
        #expect(long.hasPrefix(prefix))
        #expect(long[long.index(long.startIndex, offsetBy: prefix.count)] == " ")
        // No-ops when within budget or when no budget is set.
        #expect(PhraseFormatting.truncated("Short.", to: 72) == "Short.")
        #expect(PhraseFormatting.truncated(long, to: nil) == long)
    }

    @Test("multiple phrases avoid duplicates within the batch")
    func multiplePhrasesUnique() async {
        let engine = makeEngine()
        let phrases = await engine.selectMultiplePhrases(
            count: 3, conditionTag: .clear, tempF: 70, mode: .clean, isDay: true
        )
        #expect(phrases.count == 3)
        #expect(Set(phrases).count == 3)
    }
}

@Suite("TimeBucket + Phrase.matchesTime")
struct TimeBucketTests {

    @Test("bucket boundaries")
    func bucketBoundaries() {
        #expect(TimeBucket.from(hour: 5) == .morning)
        #expect(TimeBucket.from(hour: 10) == .morning)
        #expect(TimeBucket.from(hour: 11) == .afternoon)
        #expect(TimeBucket.from(hour: 16) == .afternoon)
        #expect(TimeBucket.from(hour: 17) == .evening)
        #expect(TimeBucket.from(hour: 20) == .evening)
        #expect(TimeBucket.from(hour: 21) == .lateNight)
        #expect(TimeBucket.from(hour: 0) == .lateNight)
        #expect(TimeBucket.from(hour: 4) == .lateNight)
    }

    private func phrase(dayOnly: Bool = false, nightOnly: Bool = false, buckets: [TimeBucket]? = nil, dates: [String]? = nil, weekdaysOnly: Bool? = nil, weekendsOnly: Bool? = nil) -> Phrase {
        Phrase(text: "t", conditions: ["any"], tempRange: nil, priority: 1,
               dayOnly: dayOnly, nightOnly: nightOnly, timeBuckets: buckets, dates: dates,
               weekdaysOnly: weekdaysOnly, weekendsOnly: weekendsOnly)
    }

    @Test("weekday/weekend gates require a known weekend signal")
    func weekendGating() {
        let officeJoke = phrase(weekdaysOnly: true)
        #expect(officeJoke.matchesTime(isDay: true, localHour: 9, isWeekend: false))
        #expect(!officeJoke.matchesTime(isDay: true, localHour: 9, isWeekend: true))
        #expect(!officeJoke.matchesTime(isDay: true, localHour: 9, isWeekend: nil))

        let brunchJoke = phrase(weekendsOnly: true)
        #expect(brunchJoke.matchesTime(isDay: true, localHour: 10, isWeekend: true))
        #expect(!brunchJoke.matchesTime(isDay: true, localHour: 10, isWeekend: false))
        #expect(!brunchJoke.matchesTime(isDay: true, localHour: 10, isWeekend: nil))

        let ungated = phrase()
        #expect(ungated.matchesTime(isDay: true, localHour: 9, isWeekend: nil))
        #expect(ungated.matchesTime(isDay: true, localHour: 9, isWeekend: true))
    }

    @Test("date gate requires a matching local month-day")
    func dateGating() {
        let julyFourth = phrase(dates: ["07-04"])
        #expect(julyFourth.matchesDate("07-04"))
        #expect(!julyFourth.matchesDate("07-05"))
        // Date-gated phrases require a known local date.
        #expect(!julyFourth.matchesDate(nil))

        let ungated = phrase()
        #expect(ungated.matchesDate(nil))
        #expect(ungated.matchesDate("01-01"))

        let christmas = phrase(dates: ["12-24", "12-25"])
        #expect(christmas.matchesDate("12-25"))
        #expect(!christmas.matchesDate("12-26"))
    }

    @Test("bucket gating layers on top of day/night booleans")
    func bucketGating() {
        let morningOnly = phrase(buckets: [.morning])
        #expect(morningOnly.matchesTime(isDay: true, localHour: 8))
        #expect(!morningOnly.matchesTime(isDay: true, localHour: 14))
        // Bucket-gated phrases require a known hour.
        #expect(!morningOnly.matchesTime(isDay: true, localHour: nil))

        let ungated = phrase()
        #expect(ungated.matchesTime(isDay: true, localHour: nil))
        #expect(ungated.matchesTime(isDay: false, localHour: 3))

        let dayGated = phrase(dayOnly: true, buckets: [.evening])
        // dayOnly loses to night even if the bucket matches evening hours.
        #expect(!dayGated.matchesTime(isDay: false, localHour: 19))
        #expect(dayGated.matchesTime(isDay: true, localHour: 19))
    }

    @Test("decoding JSON without timeBuckets leaves it nil")
    func decodeBackCompat() throws {
        let json = """
        {"text":"x","conditions":["clear"],"tempRange":null,"priority":1,"dayOnly":false,"nightOnly":false}
        """
        let p = try JSONDecoder().decode(Phrase.self, from: Data(json.utf8))
        #expect(p.timeBuckets == nil)
        #expect(p.matchesTime(isDay: true, localHour: nil))
    }
}
