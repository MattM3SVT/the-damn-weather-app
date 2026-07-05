import Foundation
import os.log

private let phraseLog = Logger(subsystem: "DamnWeather", category: "PhraseEngine")

/// Phrase display helpers usable from any target and isolation context.
public enum PhraseFormatting {
    /// If `maxLength` is set and the string exceeds it, truncate at the last
    /// word boundary within the budget and append an ellipsis. Preserves
    /// whole-word integrity so "Lazy bastard." never becomes "Lazy". Display
    /// layers (widget fallback paths) use this to defensively cut cached
    /// phrases that predate the shorter tiers — a word-boundary "…" beats
    /// iOS clipping a phrase mid-word.
    public static func truncated(_ text: String, to maxLength: Int?) -> String {
        guard let maxLength, text.count > maxLength else { return text }
        // Reserve room for the ellipsis glyph itself.
        let budget = max(1, maxLength - 1)
        let prefix = String(text.prefix(budget))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return prefix + "…"
    }
}

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
///
/// Dedup strategy:
/// - Seen phrases are tracked **per condition** (e.g., "clear", "rain") so that
///   a small pool like "clear" (220 phrases) doesn't get exhausted by phrases
///   selected for other conditions filling up the global seen list.
/// - Each condition's seen window is capped at half its pool size (max 100),
///   guaranteeing at least 50% of phrases are always available as "unseen."
/// - Preview/throwaway phrases (e.g., city card previews in saved locations list)
///   can be generated with `trackAsSeen: false` so they don't pollute the dedup.
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

    /// Max seen phrases per condition bucket. Capped to ensure at least 50% of the
    /// pool is always available as "unseen."
    private let maxSeenPerCondition = 100

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Restore last-shown phrases from persistence
        lastShownClean = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastShownClean)
        lastShownExplicit = defaults.string(forKey: AppConstants.UserDefaultsKeys.lastShownExplicit)
    }

    /// One-time migration of seen-phrase state from `.standard` (where the
    /// app's engine historically kept it) into the App Group suite that the
    /// widget's engine already uses. Sharing one dedup domain means the
    /// widget stops repeating phrases the app just showed. Keys already
    /// present in the group (widget got there first) are left alone — losing
    /// a little dedup history is harmless, silently overwriting isn't.
    nonisolated public static func migrateSeenStateToAppGroup() {
        guard let group = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        let standard = UserDefaults.standard
        let keys = [
            AppConstants.UserDefaultsKeys.seenPhrasesClean,
            AppConstants.UserDefaultsKeys.seenPhrasesExplicit,
            AppConstants.UserDefaultsKeys.lastShownClean,
            AppConstants.UserDefaultsKeys.lastShownExplicit,
        ]
        for key in keys where group.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) {
                group.set(value, forKey: key)
            }
        }
    }

    /// Load phrase bundles from the package's Resources
    public func loadIfNeeded() {
        guard !isLoaded else { return }

        if let cleanURL = Bundle.module.url(forResource: "phrases-clean", withExtension: "json") {
            do {
                let cleanData = try Data(contentsOf: cleanURL)
                cleanPhrases = try JSONDecoder().decode([Phrase].self, from: cleanData)
            } catch {
                phraseLog.error("failed to load phrases-clean.json: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            phraseLog.error("phrases-clean.json not found in bundle")
        }

        if let explicitURL = Bundle.module.url(forResource: "phrases-explicit", withExtension: "json") {
            do {
                let explicitData = try Data(contentsOf: explicitURL)
                explicitPhrases = try JSONDecoder().decode([Phrase].self, from: explicitData)
            } catch {
                phraseLog.error("failed to load phrases-explicit.json: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            phraseLog.error("phrases-explicit.json not found in bundle")
        }

        isLoaded = true
        _isReady.set()

        // Migrate old flat seen-phrase format to new per-condition format
        migrateSeenPhrasesIfNeeded()
    }

    /// Pre-load phrase JSON so subsequent `selectPhrase()` calls complete instantly.
    /// Call from a background Task to warm up the engine without blocking the caller.
    public func warmUp() {
        loadIfNeeded()
    }

    /// Select a phrase based on current weather conditions and time of day.
    /// Direct port of selectPhrase() from the website's phrases.js (lines 81-167).
    ///
    /// - Parameter trackAsSeen: Whether to mark the selected phrase as "seen" for dedup.
    ///   Pass `false` for throwaway/preview phrases (e.g., city card previews in saved locations).
    public func selectPhrase(
        conditionTag: WeatherConditionTag,
        tempF: Double,
        mode: PhraseMode = .clean,
        isDay: Bool = true,
        localHour: Int? = nil,
        localMonthDay: String? = nil,
        localIsWeekend: Bool? = nil,
        maxLength: Int? = nil,
        trackAsSeen: Bool = true
    ) -> String {
        loadIfNeeded()

        let pool = mode == .explicit ? explicitPhrases : cleanPhrases
        let condition = conditionTag.rawValue
        let seen = trackAsSeen ? getSeenPhrases(mode: mode, condition: condition) : []
        let lastShown = mode == .explicit ? lastShownExplicit : lastShownClean

        // Step 1: Filter by condition AND temperature range AND day/night
        var matches = pool.filter { p in
            p.matchesCondition(conditionTag) && p.matchesTemp(tempF) && p.matchesTime(isDay: isDay, localHour: localHour, isWeekend: localIsWeekend) && p.matchesDate(localMonthDay)
        }

        // Step 2: If no matches, relax to condition-only (still respecting day/night)
        if matches.isEmpty {
            matches = pool.filter { p in
                p.matchesCondition(conditionTag) && p.matchesTime(isDay: isDay, localHour: localHour, isWeekend: localIsWeekend) && p.matchesDate(localMonthDay)
            }
        }

        // Step 3: If still empty, fall back to temperature-range phrases (respecting day/night)
        if matches.isEmpty {
            matches = pool.filter { p in
                guard p.tempRange != nil else { return false }
                return p.matchesTemp(tempF) && p.matchesTime(isDay: isDay, localHour: localHour, isWeekend: localIsWeekend) && p.matchesDate(localMonthDay)
            }
        }

        // Step 4: If still nothing, use generic phrases (respecting day/night)
        if matches.isEmpty {
            matches = pool.filter { p in
                p.conditions.contains("any") && p.matchesTime(isDay: isDay, localHour: localHour, isWeekend: localIsWeekend) && p.matchesDate(localMonthDay)
            }
        }

        // Step 5: Last resort -- any phrase that matches day/night.
        // We deliberately stop here rather than falling through to the whole
        // pool so a `dayOnly` phrase can never fire at midnight. If even step
        // 5 yields nothing (impossible in practice given hundreds of ungated
        // candidates, but defended), the deterministic guard string below
        // takes over.
        if matches.isEmpty {
            matches = pool.filter { p in
                p.matchesTime(isDay: isDay, localHour: localHour, isWeekend: localIsWeekend) && p.matchesDate(localMonthDay)
            }
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

        // Remove recently seen phrases for this condition (if we still have enough left)
        if trackAsSeen {
            let unseen = matches.filter { p in !seen.contains(p.text) }
            if unseen.count >= 1 {
                matches = unseen
            }
        }

        // Build weighted pool (priority 2 = 2x weight). Date-gated phrases
        // that matched today get a further 6x boost: a holiday has maybe a
        // dozen phrases against hundreds of generic candidates, and without
        // the boost they'd almost never surface on their one day.
        var weighted: [Phrase] = []
        for phrase in matches {
            var weight = phrase.priority == 2 ? 2 : 1
            if let dates = phrase.dates, !dates.isEmpty {
                weight *= 6
            }
            for _ in 0..<weight {
                weighted.append(phrase)
            }
        }

        // Guard against empty pool
        guard !weighted.isEmpty else {
            let safeTempF = tempF.isFinite ? Int(tempF.rounded()) : 0
            return "It's \(safeTempF)\u{00B0} outside. That's the weather."
        }

        // True random selection
        let selected = weighted[Int.random(in: 0..<weighted.count)]

        // Replace [temp] token with actual temperature
        let text = selected.rendered(tempF: tempF)

        // Track this phrase as seen and as last-shown (persisted to prevent repeats across launches)
        if trackAsSeen {
            markSeen(mode: mode, condition: condition, phraseText: selected.text)
            if mode == .explicit {
                lastShownExplicit = selected.text
                defaults.set(selected.text, forKey: AppConstants.UserDefaultsKeys.lastShownExplicit)
            } else {
                lastShownClean = selected.text
                defaults.set(selected.text, forKey: AppConstants.UserDefaultsKeys.lastShownClean)
            }
        }

        // Hard enforce maxLength. The earlier filter is best-effort and drops itself
        // when no candidates qualify — if that happened, truncate at the last word
        // boundary so the small widget never has to cut mid-word.
        return truncate(text, to: maxLength)
    }

    private func truncate(_ text: String, to maxLength: Int?) -> String {
        PhraseFormatting.truncated(text, to: maxLength)
    }

    /// Generate multiple unique phrases for widget timeline entries.
    /// Each phrase avoids repeating the previous ones in the batch.
    /// These extra phrases are NOT tracked as "seen" — only the primary phrase
    /// selection (in selectPhrase with default trackAsSeen: true) affects dedup.
    public func selectMultiplePhrases(
        count: Int,
        conditionTag: WeatherConditionTag,
        tempF: Double,
        mode: PhraseMode = .clean,
        isDay: Bool = true,
        localHour: Int? = nil,
        localMonthDay: String? = nil,
        localIsWeekend: Bool? = nil
    ) -> [String] {
        var phrases: [String] = []
        var seen = Set<String>()
        // Try up to 3× count re-rolls before accepting a duplicate — prevents
        // an infinite loop when the filtered pool is smaller than `count`.
        let maxAttempts = count * 3
        var attempts = 0
        while phrases.count < count && attempts < maxAttempts {
            attempts += 1
            let phrase = selectPhrase(
                conditionTag: conditionTag,
                tempF: tempF,
                mode: mode,
                isDay: isDay,
                localHour: localHour,
                localMonthDay: localMonthDay,
                localIsWeekend: localIsWeekend,
                trackAsSeen: false  // Only primary phrase selection tracks
            )
            if seen.insert(phrase).inserted {
                phrases.append(phrase)
            }
        }
        // Pool smaller than requested count — pad with repeats rather than returning fewer.
        while phrases.count < count {
            phrases.append(phrases.last ?? "")
        }
        return phrases
    }

    // MARK: - Per-Condition Seen Phrases Tracking

    /// Get seen phrases for a specific condition bucket.
    private func getSeenPhrases(mode: PhraseMode, condition: String) -> [String] {
        let allSeen = getAllSeenPhrases(mode: mode)
        return allSeen[condition] ?? []
    }

    /// Mark a phrase as seen under a specific condition bucket.
    private func markSeen(mode: PhraseMode, condition: String, phraseText: String) {
        var allSeen = getAllSeenPhrases(mode: mode)
        var conditionSeen = allSeen[condition] ?? []
        conditionSeen.append(phraseText)

        // Cap at maxSeenPerCondition — FIFO rolling window
        if conditionSeen.count > maxSeenPerCondition {
            conditionSeen.removeFirst(conditionSeen.count - maxSeenPerCondition)
        }

        allSeen[condition] = conditionSeen
        saveAllSeenPhrases(mode: mode, allSeen: allSeen)
    }

    /// Read the full per-condition seen dictionary from UserDefaults.
    private func getAllSeenPhrases(mode: PhraseMode) -> [String: [String]] {
        let key = mode == .explicit
            ? AppConstants.UserDefaultsKeys.seenPhrasesExplicit
            : AppConstants.UserDefaultsKeys.seenPhrasesClean

        guard let data = defaults.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Write the full per-condition seen dictionary to UserDefaults.
    private func saveAllSeenPhrases(mode: PhraseMode, allSeen: [String: [String]]) {
        let key = mode == .explicit
            ? AppConstants.UserDefaultsKeys.seenPhrasesExplicit
            : AppConstants.UserDefaultsKeys.seenPhrasesClean

        if let data = try? JSONEncoder().encode(allSeen) {
            defaults.set(data, forKey: key)
        }
    }

    /// One-time migration: if UserDefaults has old flat [String] format, clear it
    /// so the new per-condition [String: [String]] format takes over.
    private func migrateSeenPhrasesIfNeeded() {
        for key in [AppConstants.UserDefaultsKeys.seenPhrasesClean,
                    AppConstants.UserDefaultsKeys.seenPhrasesExplicit] {
            guard let data = defaults.data(forKey: key) else { continue }
            // Try decoding as the NEW format first
            if (try? JSONDecoder().decode([String: [String]].self, from: data)) != nil {
                continue  // Already in new format
            }
            // Try decoding as the OLD flat format
            if (try? JSONDecoder().decode([String].self, from: data)) != nil {
                // Old format found — clear it to start fresh with new format
                defaults.removeObject(forKey: key)
            }
        }
    }
}
