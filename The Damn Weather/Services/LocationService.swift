import Foundation
import CoreLocation
import MapKit
import os.log

nonisolated private let locationLog = Logger(subsystem: "DamnWeather", category: "LocationService")

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

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

    /// Maximum time to wait for `CLLocationManager.requestLocation()` before
    /// falling back to the system's last-known fix. Keeps cold launch bounded:
    /// on poor GPS signal, `requestLocation()` alone can hang for 10+ seconds.
    private static let locationRequestTimeout: TimeInterval = 5

    /// Maximum age of a system-cached `CLLocationManager.location` we'll accept
    /// as a fallback when the fresh request times out. Ten minutes is long
    /// enough to cover a brief GPS cold-start slump but short enough that
    /// we're not showing weather from a previous trip.
    private static let lastKnownMaxAge: TimeInterval = 10 * 60

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

        // Race the real GPS request against a timeout. If the timeout wins,
        // fall back to the system's last-known fix (if recent enough).
        // The GPS task is explicitly @MainActor because `locationContinuation`
        // and `manager` are main-actor-isolated properties of this @Observable
        // class; the timeout task just sleeps and is fine off-actor.
        let result: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return nil }
                return try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
                    // Cancel any pending continuation so it can't hang forever.
                    self.locationContinuation?.resume(throwing: LocationError.cancelled)
                    self.locationContinuation = continuation
                    self.manager.requestLocation()
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.locationRequestTimeout))
                return nil // timeout sentinel
            }
            for await next in group {
                group.cancelAll()
                return next
            }
            return nil
        }

        if let result {
            return result
        }

        // Timeout — try the system's last-known fix before giving up.
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < Self.lastKnownMaxAge {
            locationLog.info("requestLocation timed out after \(Self.locationRequestTimeout)s; using last-known fix from \(cached.timestamp, privacy: .public)")
            return cached
        }

        locationLog.error("requestLocation timed out with no usable last-known fix")
        throw LocationError.timeout
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
        guard let location = locations.first else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
