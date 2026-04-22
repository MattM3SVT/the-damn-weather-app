import Foundation

/// Holds the AirNow API key used by `AirQualityService`. The key is looked up
/// in two places, in order:
///
/// 1. The `AIRNOW_API_KEY` environment variable (set on the Xcode scheme for
///    local dev, or in CI). Preferred because it never lives in source.
/// 2. The `hardcodedKey` constant below, which is committed as `nil`. If you
///    must hardcode during development, set the value here and run:
///
///        git update-index --skip-worktree \
///            "WeatherShared/Sources/WeatherShared/AirNowSecrets.swift"
///
///    so the modified file is not committed by accident.
///
/// When both lookups return nil, `AirQualityService` silently disables the
/// air-quality feature (the card is absent, no errors shown).
///
/// To get a free key: register at https://docs.airnowapi.org/login
public enum AirNowSecrets {
    public static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["AIRNOW_API_KEY"],
           !env.isEmpty {
            return env
        }
        return hardcodedKey
    }

    private static let hardcodedKey: String? = nil
}
