import Foundation
import WeatherShared
import os.log

private let reviewLog = Logger(subsystem: "DamnWeather", category: "ReviewPrompt")

/// Decides whether and when to call `requestReview()`. The OS owns the actual
/// prompt UI and limits it to 3 displays per 365 days; on top of that we add
/// a stricter "one time ever" rule per the product requirement, plus
/// engagement gates so we only ask after the user has seen the app deliver
/// real value.
///
/// Eligibility (all must hold):
///  - We've never called `requestReview()` before (`hasPrompted == false`).
///  - The user has had at least `minSuccessfulFetches` non-partial weather
///    loads — i.e. they came back to the app and saw it work multiple times.
///  - At least `minDaysSinceInstall` days have passed since first launch, so
///    we're never asking in the first session.
///  - The current snapshot is non-partial (the "wow moment" is on screen).
///  - There's no active severe-weather alert (don't ask during a "grr moment").
///  - The view model isn't loading / refreshing (don't interrupt a fetch).
///
/// We don't try to detect whether the OS actually displayed the sheet — Apple
/// doesn't tell us. We mark `hasPrompted = true` the moment we call
/// `requestReview()` so worst case (user disabled in-app reviews globally)
/// we still only "spend" the call once.
@Observable
final class ReviewPromptCoordinator {
    /// Cumulative non-partial weather fetches this user has seen. Increments
    /// from `WeatherViewModel` after a successful load, capped at
    /// `minSuccessfulFetches` so we never write past the gate.
    private(set) var successfulFetchCount: Int

    /// Set true the first time `markPromptedAndRequestReview` runs. Persisted.
    private(set) var hasPrompted: Bool

    /// First-launch timestamp. Written once on init when the key is missing.
    private let firstLaunchDate: Date

    private let defaults: UserDefaults

    // MARK: - Tunables

    /// Minimum non-partial fetches before we'll consider asking. Three is enough
    /// to show "they came back and saw the app work" without dragging it out.
    private let minSuccessfulFetches = 3

    /// Days since first install before we'll consider asking. Two is enough to
    /// guarantee we never ask in the first session.
    private let minDaysSinceInstall: TimeInterval = 2 * 86_400

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Anchor first-launch on the very first init. Never overwrite.
        if let stored = defaults.object(forKey: AppConstants.UserDefaultsKeys.reviewFirstLaunchDate) as? Date {
            self.firstLaunchDate = stored
        } else {
            let now = Date()
            defaults.set(now, forKey: AppConstants.UserDefaultsKeys.reviewFirstLaunchDate)
            self.firstLaunchDate = now
        }

        self.successfulFetchCount = defaults.integer(forKey: AppConstants.UserDefaultsKeys.reviewSuccessfulFetchCount)
        self.hasPrompted = defaults.bool(forKey: AppConstants.UserDefaultsKeys.reviewHasPrompted)
    }

    /// Increment the success counter (capped at the gate). Called by the
    /// view model when a non-partial snapshot lands. Cheap to call —
    /// short-circuits once we've already prompted or hit the cap.
    func recordSuccessfulFetch() {
        guard !hasPrompted else { return }
        guard successfulFetchCount < minSuccessfulFetches else { return }
        successfulFetchCount += 1
        defaults.set(successfulFetchCount, forKey: AppConstants.UserDefaultsKeys.reviewSuccessfulFetchCount)
    }

    /// Returns true when every eligibility gate is satisfied. Pure read —
    /// safe to call from anywhere, no side effects.
    func shouldRequestReview(isLoading: Bool, snapshotIsPartial: Bool, hasActiveAlert: Bool) -> Bool {
        guard !hasPrompted else { return false }
        guard successfulFetchCount >= minSuccessfulFetches else { return false }
        guard Date().timeIntervalSince(firstLaunchDate) >= minDaysSinceInstall else { return false }
        guard !snapshotIsPartial else { return false }
        guard !hasActiveAlert else { return false }
        guard !isLoading else { return false }
        return true
    }

    /// Persist the "we've asked" flag. Caller is responsible for calling the
    /// `requestReview` environment action immediately after; we separate the
    /// two because the env action lives in the SwiftUI view layer.
    func markPrompted() {
        guard !hasPrompted else { return }
        hasPrompted = true
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.reviewHasPrompted)
        reviewLog.info("Marked hasPrompted=true (fetches=\(self.successfulFetchCount), daysSinceInstall=\(Int(Date().timeIntervalSince(self.firstLaunchDate) / 86_400)))")
    }

    #if DEBUG
    /// DEBUG-only: wipe all three review-prompt keys so the trigger can be
    /// re-tested on the same install. Wired into Settings → Debug.
    func resetForDebug() {
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.reviewFirstLaunchDate)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.reviewSuccessfulFetchCount)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.reviewHasPrompted)
        successfulFetchCount = 0
        hasPrompted = false
        reviewLog.info("Reset review prompt state (DEBUG)")
    }
    #endif
}
