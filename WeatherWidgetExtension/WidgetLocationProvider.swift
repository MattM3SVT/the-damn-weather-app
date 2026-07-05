import CoreLocation
import os.log

/// Async bridge around `CLLocationManager.requestLocation()` for use inside a
/// WidgetKit timeline provider.
///
/// Requirements:
/// - Widget's Info.plist must set `NSWidgetWantsLocation = true`.
/// - Parent app's Info.plist must have `NSLocationWhenInUseUsageDescription`.
/// - User must have granted the app location permission.
///
/// Ownership note: the `CLLocationManager` delegate protocol keeps only weak
/// references. The widget provider MUST hold this provider as an instance
/// property so delegate callbacks survive past `getTimeline`/`fetchWeatherEntry`.
final class WidgetLocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    /// Guarded by `continuationLock`. CLLocationManager callbacks fire on the
    /// thread that created the manager, but we also resume from async contexts,
    /// so an explicit lock makes thread-safety compiler-enforceable rather than
    /// a documentation-only invariant.
    private let continuationLock = NSLock()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private let log = Logger(subsystem: "DamnWeather", category: "WidgetLocation")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // weather doesn't need meters
    }

    /// Atomic replace: returns the previous continuation (if any), so caller can
    /// resume it without holding the lock during resume (avoids reentrancy).
    private func swapContinuation(_ new: CheckedContinuation<CLLocation?, Never>?) -> CheckedContinuation<CLLocation?, Never>? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        let old = continuation
        continuation = new
        return old
    }

    /// Returns the device's current location, or nil if unavailable.
    /// Falls back to the system's last-known cached location if an on-demand
    /// request doesn't resolve within ~8 seconds (widget time budget is tight).
    func currentLocation() async -> CLLocation? {
        guard manager.isAuthorizedForWidgetUpdates else {
            log.info("widget not authorized for location updates")
            return nil
        }

        // Fast path: system has a recent cached fix we can use immediately.
        // `requestLocation()` can take up to 30s on cold start which is too
        // slow for a widget render, so we prefer the cache when available.
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < 5 * 60 {
            log.debug("using cached CLLocation (\(cached.timestamp))")
            return cached
        }

        // Slow path: ask for a fresh fix with a time budget. The timeout
        // resumes the pending continuation directly — racing in a task group
        // wouldn't work because the group implicitly awaits the continuation
        // child on exit and CheckedContinuation ignores cancellation, so the
        // budget would silently stretch to however long CoreLocation takes.
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.swapContinuation(nil)?.resume(returning: nil)
        }
        defer { timeoutTask.cancel() }
        return await requestLocationAsync()
    }

    private func requestLocationAsync() async -> CLLocation? {
        await withCheckedContinuation { cont in
            // Replace any pending continuation — only one in flight at a time.
            let previous = swapContinuation(cont)
            previous?.resume(returning: nil)
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let result = locations.last
        log.debug("didUpdateLocations — returning \(result.map(String.init(describing:)) ?? "nil")")
        swapContinuation(nil)?.resume(returning: result)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("didFailWithError: \(String(describing: error), privacy: .public)")
        swapContinuation(nil)?.resume(returning: nil)
    }
}
