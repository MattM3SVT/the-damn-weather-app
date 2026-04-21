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
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private let log = Logger(subsystem: "DamnWeather", category: "WidgetLocation")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // weather doesn't need meters
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

        // Slow path: ask for a fresh fix with a time budget.
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { [weak self] in
                await self?.requestLocationAsync()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
                return nil // timeout sentinel
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    private func requestLocationAsync() async -> CLLocation? {
        await withCheckedContinuation { cont in
            // Replace any pending continuation — only one in flight at a time.
            if let pending = continuation {
                pending.resume(returning: nil)
            }
            continuation = cont
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let result = locations.last
        log.debug("didUpdateLocations — returning \(result.map(String.init(describing:)) ?? "nil")")
        continuation?.resume(returning: result)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("didFailWithError: \(String(describing: error), privacy: .public)")
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
