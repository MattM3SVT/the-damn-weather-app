import Foundation

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

    /// Check if this phrase matches the given condition tag
    nonisolated public func matchesCondition(_ tag: WeatherConditionTag) -> Bool {
        conditions.contains(tag.rawValue)
    }

    /// Check if temperature falls within this phrase's range (if specified)
    nonisolated public func matchesTemp(_ tempF: Double) -> Bool {
        guard let range = tempRange, range.count == 2 else { return true }
        return tempF >= range[0] && tempF <= range[1]
    }

    /// Check if this phrase is appropriate for the current time of day
    nonisolated public func matchesTimeOfDay(isDay: Bool) -> Bool {
        if isDay { return !nightOnly }
        return !dayOnly
    }

    /// Render the phrase with the actual temperature substituted
    nonisolated public func rendered(tempF: Double) -> String {
        text.replacingOccurrences(of: "[temp]", with: "\(Int(tempF.rounded()))")
    }
}

public enum PhraseMode: String, Codable, CaseIterable, Sendable {
    case clean
    case explicit

    public var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .explicit: return "Explicit (18+)"
        }
    }
}
