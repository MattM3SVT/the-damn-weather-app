import Foundation

/// Finer-grained slice of the day than the `dayOnly`/`nightOnly` booleans.
/// Boundaries are in the *location's* local time (the engine derives the
/// hour from the weather snapshot's timezone, not the device clock), so a
/// "morning coffee" phrase for a saved city fires during that city's morning.
public enum TimeBucket: String, Codable, Sendable, CaseIterable {
    case morning     // 5:00–10:59
    case afternoon   // 11:00–16:59
    case evening     // 17:00–20:59
    case lateNight   // 21:00–4:59

    public static func from(hour: Int) -> TimeBucket {
        switch hour {
        case 5..<11:  return .morning
        case 11..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .lateNight
        }
    }
}

/// A weather phrase with matching criteria.
/// Decoded from phrases-clean.json and phrases-explicit.json.
public struct Phrase: Codable, Identifiable, Sendable {
    public var id: String { text }

    public let text: String
    public let conditions: [String]
    public let tempRange: [Double]?
    public let priority: Int
    public let dayOnly: Bool
    public let nightOnly: Bool
    /// Optional finer gate on top of dayOnly/nightOnly. Absent (the vast
    /// majority of phrases) means "any hour that satisfies the booleans".
    /// Present means the phrase fires only inside the listed buckets — and
    /// never when the caller can't supply a local hour, so a bucket-gated
    /// phrase can't leak into an unknown-time context.
    public let timeBuckets: [TimeBucket]?

    /// Optional calendar gate: "MM-dd" strings in the location's local date
    /// (e.g. ["07-04"] or ["12-24", "12-25"]). A date-gated phrase fires only
    /// on the listed days, and never when the caller can't supply the local
    /// date. The engine boosts matched date phrases in the weighted pool so
    /// a July 4th phrase actually shows up on July 4th without drowning out
    /// everything else.
    public let dates: [String]?

    /// Check if this phrase matches the given condition tag
    nonisolated public func matchesCondition(_ tag: WeatherConditionTag) -> Bool {
        conditions.contains(tag.rawValue)
    }

    /// Check if temperature falls within this phrase's range (if specified)
    nonisolated public func matchesTemp(_ tempF: Double) -> Bool {
        guard let range = tempRange, range.count == 2 else { return true }
        return tempF >= range[0] && tempF <= range[1]
    }

    /// Check if this phrase is appropriate for the current time: the
    /// day/night booleans first, then the optional bucket gate when the
    /// caller knows the location-local hour.
    nonisolated public func matchesTime(isDay: Bool, localHour: Int?) -> Bool {
        if isDay && nightOnly { return false }
        if !isDay && dayOnly { return false }
        if let buckets = timeBuckets, !buckets.isEmpty {
            guard let localHour else { return false }
            return buckets.contains(TimeBucket.from(hour: localHour))
        }
        return true
    }

    /// Check the optional calendar gate. Ungated phrases always pass;
    /// date-gated phrases require a known local "MM-dd" that's listed.
    nonisolated public func matchesDate(_ localMonthDay: String?) -> Bool {
        guard let dates, !dates.isEmpty else { return true }
        guard let localMonthDay else { return false }
        return dates.contains(localMonthDay)
    }

    /// Render the phrase with the actual temperature substituted
    nonisolated public func rendered(tempF: Double) -> String {
        let safeTempF = tempF.isFinite ? Int(tempF.rounded()) : 0
        return text.replacingOccurrences(of: "[temp]", with: "\(safeTempF)")
    }
}

public enum PhraseMode: String, Codable, CaseIterable, Sendable {
    case clean
    case explicit

    public var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .explicit: return "Explicit"
        }
    }
}
