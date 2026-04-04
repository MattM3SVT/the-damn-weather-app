import Foundation
import CoreLocation
import MapKit

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

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
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

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Location permission was denied. Enable it in Settings."
            }
        }
    }

    func reverseGeocode(_ location: CLLocation) async -> (name: String, state: String, country: String) {
        // Try iOS 26 MKReverseGeocodingRequest first
        if #available(iOS 26, *) {
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
                #if DEBUG
                print("📍 MKReverseGeocodingRequest failed: \(error). Falling back to CLGeocoder.")
                #endif
            }
        }

        // Fallback to CLGeocoder (stable, works on all versions)
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
            #if DEBUG
            print("📍 CLGeocoder also failed: \(error). Returning defaults.")
            #endif
            return ("Unknown", "", "")
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
