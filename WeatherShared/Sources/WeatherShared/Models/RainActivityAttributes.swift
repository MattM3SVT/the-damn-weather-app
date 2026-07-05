#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity for imminent precipitation: "Rain starting in ~12 minutes"
/// counting down in the Dynamic Island and on the lock screen.
///
/// Lives in WeatherShared because the APP starts/updates the activity while
/// the WIDGET EXTENSION renders it — ActivityKit matches them by the
/// attributes type, so both processes must see the identical declaration.
///
/// Lifecycle (foreground-armed; no push updates):
///  - Started when a fresh fetch shows precipitation beginning within the
///    next hour at the device's location.
///  - Updated on subsequent fetches if the onset time shifts.
///  - Ended (with a short "it's here" state) once the onset passes, or
///    dismissed by iOS at `staleDate` if the app never gets another look.
public struct RainActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When precipitation is expected to begin. Views render a live
        /// countdown against this via `Text(timerInterval:)`.
        public var startsAt: Date
        /// True once `startsAt` has passed and we're showing "it's here".
        public var hasStarted: Bool

        public init(startsAt: Date, hasStarted: Bool) {
            self.startsAt = startsAt
            self.hasStarted = hasStarted
        }
    }

    /// "Rain" or "Snow" — chosen at start time from the forecast condition.
    public var kind: String
    public var locationName: String

    public init(kind: String, locationName: String) {
        self.kind = kind
        self.locationName = locationName
    }
}
#endif
