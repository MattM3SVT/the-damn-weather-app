import Foundation

/// Thread-safe wrapper so `isReady` can be read outside the actor without `await`.
private final class ReadyFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}

/// Phrase selection engine -- exact port of the website's phrases.js algorithm.
/// Uses a 6-step cascading filter to find the best phrase match.
public actor PhraseEngine {
    private var cleanPhrases: [Phrase] = []
    private var explicitPhrases: [Phrase] = []
    private var isLoaded = false

    /// Thread-safe flag readable outside the actor (no await needed).
    /// Used by the widget to check if JSON is already loaded before entering a Task.
    private let _isReady = ReadyFlag()

    /// Whether phrase JSON has already been loaded into memory.
    /// Can be read synchronously from any context (nonisolated).
    nonisolated public var isReady: Bool { _isReady.value }

    /// Tracks the last phrase shown per mode to prevent back-to-back repeats (persisted)
    private var lastShownClean: String?
    private var lastShownExplicit: String?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Restore last-shown phrases from persistence
        lastShownClean = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastShownClean)
        lastShownExplicit = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastShownExplicit)
    }

    /// Load phrase bundles from the package's Resources
    public func loadIfNeeded() {
        guard !isLoaded else { return }

        if let cleanURL = Bundle.module.url(forResource: "phrases-clean", withExtension: "json") {
            do {
                let cleanData = try Data(contentsOf: cleanURL)
                cleanPhrases = try JSONDecoder().decode([Phrase].self, from: cleanData)
            } catch {
                #if DEBUG
                print("⚠️ PhraseEngine: Failed to load phrases-clean.json: \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("⚠️ PhraseEngine: phrases-clean.json not found in bundle")
            #endif
        }

        if let explicitURL = Bundle.module.url(forResource: "phrases-explicit", withExtension: "json") {
            do {
                let explicitData = try Data(contentsOf: explicitURL)
                explicitPhrases = try JSONDecoder().decode([Phrase].self, from: explicitData)
            } catch {
                #if DEBUG
                print("⚠️ PhraseEngine: Failed to load phrases-explicit.json: \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("⚠️ PhraseEngine: phrases-explicit.json not found in bundle")
            #endif
        }

        isLoaded = true
        _isReady.set()
    }

    /// Pre-load phrase JSON so subsequent `selectPhrase()` calls complete instantly.
    /// Call from a background Task to warm up the engine without blocking the caller.
    public func warmUp() {
        loadIfNeeded()
    }

    /// Select a phrase based on current weather conditions and time of day.
    /// Direct port of selectPhrase() from the website's phrases.js (lines 81-167).
    public func selectPhrase(
        conditionTag: WeatherConditionTag,
        tempF: Double,
        mode: PhraseMode = .clean,
        isDay: Bool = true,
        maxLength: Int? = nil
    ) -> String {
        loadIfNeeded()

        let pool = mode == .explicit ? explicitPhrases : cleanPhrases
        let seen = getSeenPhrases(mode: mode)
        let lastShown = mode == .explicit ? lastShownExplicit : lastShownClean

        // Step 1: Filter by condition AND temperature range AND day/night
        var matches = pool.filter { p in
            p.matchesCondition(conditionTag) && p.matchesTemp(tempF) && p.matchesTimeOfDay(isDay: isDay)
        }

        // Step 2: If no matches, relax to condition-only (still respecting day/night)
        if matches.isEmpty {
            matches = pool.filter { p in
                p.matchesCondition(conditionTag) && p.matchesTimeOfDay(isDay: isDay)
            }
        }

        // Step 3: If still empty, fall back to temperature-range phrases (respecting day/night)
        if matches.isEmpty {
            matches = pool.filter { p in
                guard p.tempRange != nil else { return false }
                return p.matchesTemp(tempF) && p.matchesTimeOfDay(isDay: isDay)
            }
        }

        // Step 4: If still nothing, use generic phrases (respecting day/night)
        if matches.isEmpty {
            matches = pool.filter { p in
                p.conditions.contains("any") && p.matchesTimeOfDay(isDay: isDay)
            }
        }

        // Step 5: Last resort -- any phrase that matches day/night
        if matches.isEmpty {
            matches = pool.filter { p in
                p.matchesTimeOfDay(isDay: isDay)
            }
        }

        // Step 6: Absolute last resort -- whole pool
        if matches.isEmpty {
            matches = pool
        }

        // Always exclude the last-shown phrase to prevent back-to-back repeats
        if let lastShown, matches.count > 1 {
            matches = matches.filter { $0.text != lastShown }
        }

        // Filter by max length if requested (e.g., small widget needs short phrases).
        // Only apply if we still have enough matches after filtering.
        if let maxLength {
            let shortEnough = matches.filter { $0.rendered(tempF: tempF).count <= maxLength }
            if !shortEnough.isEmpty {
                matches = shortEnough
            }
        }

        // Remove recently seen phrases (if we still have enough left)
        let unseen = matches.filter { p in !seen.contains(p.text) }
        if unseen.count >= 1 {
            matches = unseen
        }

        // Build weighted pool (priority 2 = 2x weight)
        var weighted: [Phrase] = []
        for phrase in matches {
            let weight = phrase.priority == 2 ? 2 : 1
            for _ in 0..<weight {
                weighted.append(phrase)
            }
        }

        // Guard against empty pool
        guard !weighted.isEmpty else {
            let safeTempF = tempF.isFinite ? Int(tempF.rounded()) : 0
            return "It's \(safeTempF)° outside. That's the weather."
        }

        // True random selection
        let selected = weighted[Int.random(in: 0..<weighted.count)]

        // Replace [temp] token with actual temperature
        let text = selected.rendered(tempF: tempF)

        // Track this phrase as seen and as last-shown (persisted to prevent repeats across launches)
        markSeen(mode: mode, phraseText: selected.text)
        if mode == .explicit {
            lastShownExplicit = selected.text
            defaults.set(selected.text, forKey: AppConstants.UserDefaultsKeys.lastShownExplicit)
        } else {
            lastShownClean = selected.text
            defaults.set(selected.text, forKey: AppConstants.UserDefaultsKeys.lastShownClean)
        }

        return text
    }

    /// Generate multiple unique phrases for widget timeline entries.
    /// Each phrase avoids repeating the previous ones in the batch.
    public func selectMultiplePhrases(
        count: Int,
        conditionTag: WeatherConditionTag,
        tempF: Double,
        mode: PhraseMode = .clean,
        isDay: Bool = true
    ) -> [String] {
        var phrases: [String] = []
        for _ in 0..<count {
            let phrase = selectPhrase(
                conditionTag: conditionTag,
                tempF: tempF,
                mode: mode,
                isDay: isDay
            )
            phrases.append(phrase)
        }
        return phrases
    }

    // MARK: - Seen Phrases Tracking

    private func getSeenPhrases(mode: PhraseMode) -> [String] {
        let key = mode == .explicit
            ? AppConstants.UserDefaultsKeys.seenPhrasesExplicit
            : AppConstants.UserDefaultsKeys.seenPhrasesClean

        guard let data = defaults.data(forKey: key),
              let seen = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return seen
    }

    private func markSeen(mode: PhraseMode, phraseText: String) {
        let key = mode == .explicit
            ? AppConstants.UserDefaultsKeys.seenPhrasesExplicit
            : AppConstants.UserDefaultsKeys.seenPhrasesClean

        var seen = getSeenPhrases(mode: mode)
        seen.append(phraseText)

        // Only keep the last MAX_SEEN
        if seen.count > AppConstants.maxSeenPhrases {
            seen.removeFirst(seen.count - AppConstants.maxSeenPhrases)
        }

        if let data = try? JSONEncoder().encode(seen) {
            defaults.set(data, forKey: key)
        }
    }
}
