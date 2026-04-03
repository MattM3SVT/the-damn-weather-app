import Foundation
import MapKit

@Observable
final class LocationSearchViewModel: NSObject, MKLocalSearchCompleterDelegate {
    var searchText = ""
    var results: [SearchResult] = []
    var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private let locationService: LocationService

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion?
    }

    init(locationService: LocationService) {
        self.locationService = locationService
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func updateSearch(_ text: String) {
        searchText = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            return
        }
        completer.queryFragment = text
    }

    func selectResult(_ result: SearchResult) async -> (name: String, state: String, country: String, location: CLLocation)? {
        guard let completion = result.completion else { return nil }

        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            guard let item = response.mapItems.first else { return nil }

            if #available(iOS 26, *) {
                let coord = item.location.coordinate
                let cityName = item.addressRepresentations?.cityName
                return (
                    name: cityName ?? item.name ?? result.title,
                    state: item.addressRepresentations?.cityWithContext(.short)?.replacingOccurrences(
                        of: (cityName ?? "") + ", ",
                        with: ""
                    ) ?? "",
                    country: item.addressRepresentations?.regionName ?? "",
                    location: CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                )
            } else {
                return (
                    name: item.placemark.locality ?? item.placemark.name ?? result.title,
                    state: item.placemark.administrativeArea ?? "",
                    country: item.placemark.country ?? "",
                    location: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                )
            }
        } catch {
            return nil
        }
    }

    func clear() {
        searchText = ""
        results = []
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.map { completion in
            SearchResult(
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Silently handle — search will just show no results
    }
}
