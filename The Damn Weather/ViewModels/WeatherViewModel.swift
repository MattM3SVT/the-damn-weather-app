import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import WeatherShared

@Observable
final class WeatherViewModel {
    // MARK: - State
    var weather: WeatherSnapshot?
    var locationName: String = ""
    var locationState: String = ""
    var currentPhrase: String = "Loading the attitude..."
    var isLoading = false
    var error: String?
    var currentTime: String = ""

    // MARK: - Dependencies
    private let weatherService = WeatherService()
    private let locationService: LocationService
    private let phraseEngine = PhraseEngine()
    private let appState: AppState
    private var timeTimer: Timer?

    init(locationService: LocationService, appState: AppState) {
        self.locationService = locationService
        self.appState = appState
    }

    // MARK: - Public API

    func loadWeatherForCurrentLocation() async {
        // Don't show loading state while waiting for permission — let the permission dialog appear cleanly
        let needsPermission = locationService.authorizationStatus == .notDetermined
        if !needsPermission {
            isLoading = true
        }
        error = nil

        do {
            let location = try await locationService.requestLocation()
            isLoading = true
            await loadWeather(for: location)
        } catch {
            if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                self.error = "Location access denied. Enable it in Settings → Privacy → Location Services."
            } else {
                self.error = "Couldn't get your location. Check your settings."
            }
            isLoading = false
        }
    }

    func loadWeather(for location: CLLocation) async {
        isLoading = true
        error = nil

        // Geocode runs independently — it never throws, so it can never kill weather data
        async let geocodeTask = locationService.reverseGeocode(location)

        do {
            let snapshot = try await weatherService.fetchWeather(for: location)

            // WeatherKit succeeded — use real data
            weather = snapshot

            let geocode = await geocodeTask
            locationName = geocode.name
            locationState = geocode.state

            // Save location to shared defaults for widgets
            let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
            defaults.set(location.coordinate.latitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLat)
            defaults.set(location.coordinate.longitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLon)
            defaults.set(geocode.name, forKey: AppConstants.UserDefaultsKeys.lastLocationName)

            // Generate phrase
            await refreshPhrase()

            // Start time updates
            startTimeUpdates(timezone: snapshot.timezone)

            isLoading = false
        } catch {
            let errorDesc = String(describing: error)
            print("🌦️ WeatherKit Error: \(errorDesc)")

            let geocode = await geocodeTask
            locationName = geocode.name.isEmpty ? "Unknown" : geocode.name
            locationState = geocode.state
            self.error = "Couldn't load weather data. Pull down to retry."
            isLoading = false
        }
    }

    func loadWeather(for savedLocation: SavedLocation) async {
        locationName = savedLocation.name
        locationState = savedLocation.state
        await loadWeather(for: savedLocation.clLocation)
    }

    func refreshPhrase() async {
        guard let weather else { return }
        currentPhrase = await phraseEngine.selectPhrase(
            conditionTag: weather.current.conditionTag,
            tempF: weather.current.temperature,
            mode: appState.phraseMode,
            isDay: weather.current.isDay
        )

        // Share the phrase with the widget and trigger refresh
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.set(currentPhrase, forKey: "currentPhrase")
        defaults.set(appState.phraseMode.rawValue, forKey: AppConstants.UserDefaultsKeys.phraseMode)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() async {
        guard let weather else {
            await loadWeatherForCurrentLocation()
            return
        }
        await weatherService.clearCache()
        await loadWeather(for: weather.location)
    }

    // MARK: - Computed Properties

    var displayName: String {
        if !locationState.isEmpty {
            return "\(locationName), \(locationState)"
        }
        return locationName
    }

    var hasAlerts: Bool {
        !(weather?.alerts.isEmpty ?? true)
    }

    var temperatureUnit: TemperatureUnit {
        appState.temperatureUnit
    }

    // MARK: - Time Updates

    private func startTimeUpdates(timezone: TimeZone) {
        timeTimer?.invalidate()
        currentTime = Date.currentTimeString(timezone: timezone)
        timeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.currentTime = Date.currentTimeString(timezone: timezone)
        }
    }

    deinit {
        timeTimer?.invalidate()
    }
}
