import ActivityKit
import Foundation
import WeatherShared
import os.log

nonisolated private let rainActivityLog = Logger(subsystem: "DamnWeather", category: "RainActivity")

/// Owns the rain-countdown Live Activity lifecycle. Foreground-armed: the
/// activity starts when a fetch (while the user is in the app) shows
/// precipitation beginning within the hour, updates when later fetches move
/// the onset, flips to "it's here" once precipitation begins, and cleans up
/// when the threat passes. No push channel — `staleDate` lets iOS dim it if
/// the app never gets another look.
final class RainActivityManager {
    static let shared = RainActivityManager()

    /// How long past onset the "it's here" state stays on the lock screen
    /// before iOS removes it.
    private static let lingerAfterStart: TimeInterval = 15 * 60

    /// Reconcile the activity with the latest device-location snapshot.
    /// Called from the view model after device-location fetches (always
    /// foreground contexts, which is required for `Activity.request`).
    func reconcile(with snapshot: WeatherSnapshot, locationName: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let existing = Activity<RainActivityAttributes>.activities.first
        let minutes = PrecipitationSoonBanner.minutesUntilStart(snapshot.minutePrecipitation)

        if let minutes {
            let startsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let state = RainActivityAttributes.ContentState(startsAt: startsAt, hasStarted: false)
            let content = ActivityContent(
                state: state,
                staleDate: startsAt.addingTimeInterval(Self.lingerAfterStart)
            )
            if let existing {
                await existing.update(content)
                rainActivityLog.info("updated rain activity, onset in \(minutes)m")
            } else {
                let isSnow = [.snow, .heavySnow, .freezingRain].contains(snapshot.current.conditionTag)
                    || snapshot.current.temperature <= 34
                let attributes = RainActivityAttributes(
                    kind: isSnow ? "Snow" : "Rain",
                    locationName: locationName
                )
                do {
                    _ = try Activity.request(attributes: attributes, content: content)
                    rainActivityLog.info("started rain activity, onset in \(minutes)m")
                } catch {
                    // Not enabled, too many activities, or backgrounded —
                    // all fine, the in-app banner still covers it.
                    rainActivityLog.info("could not start activity: \(String(describing: error), privacy: .public)")
                }
            }
            return
        }

        guard let existing else { return }

        // No upcoming onset in this snapshot: either it's precipitating now
        // (countdown completed) or the threat evaporated.
        let onsetPassed = existing.content.state.startsAt <= Date()
        if onsetPassed && Self.isPrecipitatingNow(snapshot) {
            let state = RainActivityAttributes.ContentState(
                startsAt: existing.content.state.startsAt,
                hasStarted: true
            )
            await existing.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(Self.lingerAfterStart))
            )
            rainActivityLog.info("rain arrived; activity ended with linger")
        } else {
            await existing.end(existing.content, dismissalPolicy: .immediate)
            rainActivityLog.info("rain threat passed; activity dismissed")
        }
    }

    /// Whether the first minute of the forecast says precipitation is
    /// happening right now (mirrors PrecipitationSoonBanner's threshold).
    private static func isPrecipitatingNow(_ snapshot: WeatherSnapshot) -> Bool {
        let now = Date()
        guard let current = snapshot.minutePrecipitation
            .filter({ $0.time >= now.addingTimeInterval(-60) })
            .min(by: { $0.time < $1.time }) else {
            // No minute data — fall back to the current condition tag.
            return [.rain, .heavyRain, .drizzle, .snow, .heavySnow, .freezingRain, .thunderstorm]
                .contains(snapshot.current.conditionTag)
        }
        return current.intensity > 0.002 && current.probability >= 50
    }
}
