import Foundation

/// A normalized sky-cover code shared by NWS and METAR observations.
/// Ordered so `rawValue` reflects increasing coverage — used for dominant-layer selection.
public enum SkyCover: Int, Sendable, Comparable {
    case clear = 0      // CLR / SKC
    case few = 1        // FEW  (1-2 octas)
    case scattered = 2  // SCT  (3-4 octas)
    case broken = 3     // BKN  (5-7 octas)
    case overcast = 4   // OVC  (8 octas)
    case obscured = 5   // VV   (vertical visibility; sky obscured)

    public static func < (lhs: SkyCover, rhs: SkyCover) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short display code ("CLR", "FEW", ...) for debug badges and logs.
    public var code: String {
        switch self {
        case .clear:     return "CLR"
        case .few:       return "FEW"
        case .scattered: return "SCT"
        case .broken:    return "BKN"
        case .overcast:  return "OVC"
        case .obscured:  return "VV"
        }
    }

    /// Parse a textual cover code from either API into our normalized enum.
    /// Returns nil for missing / unknown codes so callers can treat as "no data".
    public static func parse(_ code: String?) -> SkyCover? {
        guard let raw = code?.uppercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "CLR", "SKC", "NCD":   return .clear
        case "FEW":                 return .few
        case "SCT":                 return .scattered
        case "BKN":                 return .broken
        case "OVC":                 return .overcast
        case "VV":                  return .obscured
        default:
            #if DEBUG
            print("⚠️ SkyCover: unknown cover code \(raw)")
            #endif
            return nil
        }
    }
}

/// Combined observation result from the two ground-truth sources.
/// A nil field means that source either failed, returned no data, or was stale.
public struct SkyConsensus: Sendable {
    public let nws: SkyCover?
    public let metar: SkyCover?

    public init(nws: SkyCover?, metar: SkyCover?) {
        self.nws = nws
        self.metar = metar
    }

    /// Empty consensus — no source data available. Override always passes through.
    public static let empty = SkyConsensus(nws: nil, metar: nil)
}

/// Apply the NWS+METAR consensus override to a base WeatherConditionTag.
///
/// Bidirectional: corrects WeatherKit in either direction (too-cloudy or too-clear)
/// when both ground-truth sources agree on the actual sky state. Precipitation,
/// wind, and fog tags always pass through — a METAR cloud report doesn't
/// invalidate "it's raining".
///
/// Confidence protection: if WK's own cloud-cover reading strongly confirms its
/// base tag (≥80% for .cloudy, ≤20% for .clear), the override is suppressed.
/// This guards against microclimate mismatch where the nearest ASOS station is
/// 10+ miles from the user and sees a different sky.
///
/// Strict clear rule: only BOTH stations reporting exactly CLR triggers a
/// .clear override. CLR+FEW or FEW+FEW produces .partlyCloudy — "FEW" literally
/// means clouds are visible, so it's not truly clear sky.
public func applyConsensusOverride(
    base: WeatherConditionTag,
    consensus: SkyConsensus,
    wkCloudCoverPct: Double
) -> WeatherConditionTag {
    // 1. Only operate on sky-cover-only tags. Rain/snow/fog/wind/etc. pass through.
    guard [.clear, .partlyCloudy, .cloudy].contains(base) else { return base }

    // 2. Both sources must have succeeded. Obscured (VV) isn't a clear sky-cover
    //    signal — skip override so WK's fog/cloudy mapping stays in place.
    guard let nws = consensus.nws, let metar = consensus.metar else { return base }
    guard nws != .obscured, metar != .obscured else { return base }

    // 3. WK confidence guard. If WK's own cloudCover reading strongly agrees
    //    with its base tag, trust WK over distant ground stations.
    if base == .cloudy && wkCloudCoverPct >= AppConstants.wkHighCloudConfidenceThreshold {
        return base
    }
    if base == .clear && wkCloudCoverPct <= AppConstants.wkLowCloudConfidenceThreshold {
        return base
    }

    // 4. Derive the consensus tag from the two sources' agreement.
    //    - Both exactly CLR → .clear (strict; FEW counts as "clouds visible")
    //    - Both in {BKN, OVC} → .cloudy
    //    - Both in {CLR, FEW, SCT} (not both CLR) → .partlyCloudy
    //    - Straddle (one clear-ish, one cloudy-ish) → no agreement, no override
    let cloudyish:   Set<SkyCover> = [.broken, .overcast]
    let nonOvercast: Set<SkyCover> = [.clear, .few, .scattered]

    let consensusTag: WeatherConditionTag
    if nws == .clear && metar == .clear {
        consensusTag = .clear
    } else if cloudyish.contains(nws) && cloudyish.contains(metar) {
        consensusTag = .cloudy
    } else if nonOvercast.contains(nws) && nonOvercast.contains(metar) {
        consensusTag = .partlyCloudy
    } else {
        // Sources straddle the clear/cloudy divide (e.g. FEW + BKN). No agreement.
        return base
    }

    // 5. Override only when consensus disagrees with WK.
    return consensusTag != base ? consensusTag : base
}

/// DEBUG-only diagnostic payload describing which source produced the final tag.
/// Populated in `#if DEBUG` builds so a small overlay in the hero section can
/// show the decision path without changing release behavior.
public struct CrossCheckDebugInfo: Sendable {
    public let wkDescription: String          // "Mostly Cloudy", "Cloudy", ...
    public let baseTag: WeatherConditionTag   // what WeatherConditionTag.from returned
    public let finalTag: WeatherConditionTag  // after applyConsensusOverride
    public let nws: SkyCover?
    public let metar: SkyCover?

    public init(
        wkDescription: String,
        baseTag: WeatherConditionTag,
        finalTag: WeatherConditionTag,
        nws: SkyCover?,
        metar: SkyCover?
    ) {
        self.wkDescription = wkDescription
        self.baseTag = baseTag
        self.finalTag = finalTag
        self.nws = nws
        self.metar = metar
    }

    public var wasOverridden: Bool { baseTag != finalTag }

    /// Compact one-liner for on-screen debug badge.
    public var displayString: String {
        let nwsStr = nws?.code ?? "—"
        let metarStr = metar?.code ?? "—"
        if wasOverridden {
            return "✓ WK:\(baseTag.label) → \(finalTag.label) · NWS:\(nwsStr) · M:\(metarStr)"
        }
        return "WK:\(baseTag.label) · NWS:\(nwsStr) · M:\(metarStr)"
    }
}
