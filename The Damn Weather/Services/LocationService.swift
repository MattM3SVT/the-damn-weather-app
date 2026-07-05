import Foundation
import CoreLocation
import MapKit
import os.log

nonisolated private let locationLog = Logger(subsystem: "DamnWeather", category: "LocationService")

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    /// Timeout for the in-flight `requestLocation` call. Tracked so a newer
    /// request can cancel the previous request's timer — otherwise a stale
    /// timer could fire and spuriously fail the newer continuation.
    private var locationTimeoutTask: Task<Void, Never>?

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentLocationName: String = ""
    var currentState: String = ""

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Maximum time to wait for a fresh GPS fix before giving up.
    /// Slightly longer than the previous 5 s because the new "reject stale,
    /// wait for fresh" path can need a moment for GPS warmup beyond the
    /// initial cached delivery from CoreLocation.
    private static let locationRequestTimeout: TimeInterval = 8

    /// Maximum age of a delivered location we'll accept as "current".
    /// CoreLocation can deliver an arbitrarily-old cached fix as the first
    /// callback when it considers the cache "good enough" for the requested
    /// accuracy. That manifested as: drive an hour, return, app still thinks
    /// you're at the origin. Anything older than this is rejected and we
    /// wait for the next callback (a fresh fix).
    private static let staleFixThreshold: TimeInterval = 30

    /// Maximum age of `CLLocationManager.location` we'll accept as a fallback
    /// when our fresh-fix attempt times out. Tightened from 10 min to 60 s —
    /// the old window let a 9-minute-old "previous city" fix slip through
    /// after a long drive. If the GPS hasn't produced a fix in the last
    /// minute, prefer throwing over silently showing wrong-city weather.
    private static let lastKnownMaxAge: TimeInterval = 60

    func requestLocation() async throws -> CLLocation {
        // Wait for permission if not yet determined
        if authorizationStatus == .notDetermined {
            requestPermission()
            // Wait for the user to respond to the permission dialog
            try await waitForAuthorization()
        }

        // Check if permission was denied
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }

        // Use `startUpdatingLocation` rather than `requestLocation`:
        // `requestLocation` only delivers a single callback, so if that
        // first callback is a stale cached fix (which CoreLocation routinely
        // serves when desiredAccuracy is met by the cache), we have no way
        // to wait for a fresher one. `startUpdatingLocation` streams updates,
        // and the delegate filters by timestamp until a fresh fix arrives.
        //
        // The timeout resumes the pending continuation directly rather than
        // racing in a task group: a group would implicitly await the GPS
        // child on exit, and a CheckedContinuation ignores cancellation, so
        // the "timeout" would silently wait for CoreLocation anyway (with
        // the GPS left running the whole time).
        locationTimeoutTask?.cancel()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.locationRequestTimeout))
            guard !Task.isCancelled else { return }
            self?.finishLocationRequest(with: .failure(LocationError.timeout))
        }
        locationTimeoutTask = timeoutTask

        // `startUpdatingLocation` runs continuously; always stop once we're
        // done (success, timeout, or supersession) so the GPS chip can power
        // down. Calling `stop` when not started is a no-op, so this is safe.
        defer {
            timeoutTask.cancel()
            manager.stopUpdatingLocation()
        }

        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
                // Cancel any pending continuation so it can't hang forever.
                locationContinuation?.resume(throwing: LocationError.cancelled)
                locationContinuation = continuation
                manager.startUpdatingLocation()
            }
        } catch LocationError.timeout {
            // Timeout — try the system's last-known fix only if it's recent
            // enough that it's plausibly current.
            if let cached = manager.location,
               Date().timeIntervalSince(cached.timestamp) < Self.lastKnownMaxAge {
                locationLog.info("requestLocation timed out after \(Self.locationRequestTimeout)s; using last-known fix from \(cached.timestamp, privacy: .public)")
                return cached
            }
            locationLog.error("requestLocation timed out with no usable last-known fix")
            throw LocationError.timeout
        }
    }

    /// Resume and clear the pending continuation exactly once. Every
    /// completion path (fresh fix, CL error, timeout) funnels through here so
    /// a late delegate callback after the timeout already fired is a no-op.
    private func finishLocationRequest(with result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        switch result {
        case .success(let location): continuation.resume(returning: location)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    /// Waits for the user to respond to the location permission dialog
    private func waitForAuthorization() async throws {
        // If already determined, return immediately
        if authorizationStatus != .notDetermined { return }

        // Poll for authorization change (the delegate updates authorizationStatus)
        for _ in 0..<300 { // Up to 30 seconds
            try await Task.sleep(for: .milliseconds(100))
            if authorizationStatus != .notDetermined {
                return
            }
        }
        throw LocationError.permissionDenied
    }

    enum LocationError: LocalizedError {
        case permissionDenied
        case cancelled
        case timeout

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Location request was superseded by a newer request."
            case .permissionDenied:
                return "Location permission was denied. Enable it in Settings."
            case .timeout:
                return "Couldn't get a location fix. Check your GPS signal or try again."
            }
        }
    }

    func reverseGeocode(_ location: CLLocation) async -> (name: String, state: String, country: String) {
        if #available(iOS 26, *) {
            // Use MKReverseGeocodingRequest on iOS 26+
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    return ("Unknown", "", "")
                }
                let mapItems = try await request.mapItems
                guard let item = mapItems.first else {
                    return ("Unknown", "", "")
                }
                return Self.extractAddress(from: item)
            } catch {
                locationLog.error("MKReverseGeocodingRequest failed: \(error.localizedDescription, privacy: .public) — returning defaults")
                return ("Unknown", "", "")
            }
        } else {
            // Fallback to CLGeocoder on older iOS versions
            do {
                let geocoder = CLGeocoder()
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let place = placemarks.first else {
                    return ("Unknown", "", "")
                }
                return (
                    name: place.locality ?? place.name ?? "Unknown",
                    state: place.administrativeArea ?? "",
                    country: place.country ?? ""
                )
            } catch {
                locationLog.error("CLGeocoder failed: \(error.localizedDescription, privacy: .public) — returning defaults")
                return ("Unknown", "", "")
            }
        }
    }

    func searchLocation(query: String) async throws -> [(name: String, state: String, country: String, location: CLLocation)] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response.mapItems.compactMap { item in
            if #available(iOS 26, *) {
                let info = Self.extractAddress(from: item)
                let coord = item.location.coordinate
                return (
                    name: info.name,
                    state: info.state,
                    country: info.country,
                    location: CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                )
            } else {
                guard let name = item.placemark.locality ?? item.placemark.name else { return nil }
                return (
                    name: name,
                    state: item.placemark.administrativeArea ?? "",
                    country: item.placemark.country ?? "",
                    location: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                )
            }
        }
    }

    // MARK: - iOS 26+ Address Extraction

    @available(iOS 26, *)
    private static func extractAddress(from item: MKMapItem) -> (name: String, state: String, country: String) {
        let city = item.addressRepresentations?.cityName ?? item.name ?? "Unknown"
        let country = item.addressRepresentations?.regionName ?? ""

        // Extract state from "City, ST" format
        let contextStyle = MKAddressRepresentations.ContextStyle.short
        let cityWithContext = item.addressRepresentations?.cityWithContext(contextStyle) ?? ""
        let state: String
        if cityWithContext.contains(", ") {
            state = String(cityWithContext.split(separator: ", ").dropFirst().joined(separator: ", "))
        } else {
            state = ""
        }

        return (name: city, state: state, country: country)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // `locations.last` is the newest in batched updates per Apple's docs.
        guard let location = locations.last else { return }

        // Reject stale cached fixes. CoreLocation often delivers an old cache
        // entry as the first update; ignoring it lets us wait for the next
        // callback (which will be the fresh GPS fix). Without this filter,
        // returning home from a long drive shows the previous city's weather
        // until the user manually refreshes a few times.
        let age = Date().timeIntervalSince(location.timestamp)
        guard age <= Self.staleFixThreshold else {
            locationLog.debug("rejected stale fix: age=\(age, privacy: .public)s")
            return
        }

        finishLocationRequest(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocationRequest(with: .failure(error))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
