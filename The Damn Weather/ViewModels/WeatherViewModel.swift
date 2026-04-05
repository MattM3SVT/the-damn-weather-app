import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import WeatherShared

@Observable
final class WeatherViewModel {
    // MARK: - State (currently displayed)
    var weather: WeatherSnapshot?
    var locationName: String = ""
    var locationState: String = ""
    var currentPhrase: String = "Loading the attitude..."
    var isLoading = false
    var error: String?
    var currentTime: String = ""

    // MARK: - Device current location state (for sidebar "My Location" card)
    var currentLocationWeather: WeatherSnapshot?
    var currentLocationName: String = ""
    var currentLocationState: String = ""
    var currentLocationPhrase: String = ""

    // MARK: - Cached saved location state (avoids re-fetching/re-phrasing on tap)
    private var savedLocationCache: [String: (weather: WeatherSnapshot, phrase: String)] = [:]

    // MARK: - Location tracking
    private(set) var isShowingDeviceLocation = false
    private var isRefreshing = false

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
        guard !isLoading else { return }  // Prevent concurrent location requests
        isShowingDeviceLocation = true

        // Don't show loading state while waiting for permission — let the permission dialog appear cleanly
        let needsPermission = locationService.authorizationStatus == .notDetermined
        if !needsPermission {
            isLoading = true
        }
        error = nil

        do {
            let location = try await locationService.requestLocation()
            isLoading = true
            await loadWeather(for: location, isDeviceLocation: true)
        } catch {
            if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                self.error = "Location access denied. Enable it in Settings → Privacy → Location Services."
            } else {
                self.error = "Couldn't get your location. Check your settings."
            }
            isLoading = false
        }
    }

    func loadWeather(for location: CLLocation, isDeviceLocation: Bool = false) async {
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

            // If this is the device's current location, save it separately for the sidebar
            if isDeviceLocation {
                currentLocationWeather = snapshot
                currentLocationName = geocode.name
                currentLocationState = geocode.state
            }

            // Save location to shared defaults for widgets
            let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
            defaults.set(location.coordinate.latitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLat)
            defaults.set(location.coordinate.longitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLon)
            defaults.set(geocode.name, forKey: AppConstants.UserDefaultsKeys.lastLocationName)

            // Generate phrase
            await refreshPhrase()

            // If this is the device location, also save the phrase for the sidebar
            if isDeviceLocation {
                currentLocationPhrase = currentPhrase
            }

            // Start time updates
            startTimeUpdates(timezone: snapshot.timezone)

            isLoading = false
        } catch {
            let errorDesc = String(describing: error)
            #if DEBUG
            print("🌦️ WeatherKit Error: \(errorDesc)")
            #endif

            let geocode = await geocodeTask
            locationName = geocode.name.isEmpty ? "Unknown" : geocode.name
            locationState = geocode.state
            self.error = "Couldn't load weather data. Pull down to retry."
            isLoading = false
        }
    }

    /// Switch back to showing the device's current location without re-fetching.
    func showCurrentLocation() {
        isShowingDeviceLocation = true
        guard let currentLocationWeather else { return }
        weather = currentLocationWeather
        locationName = currentLocationName
        locationState = currentLocationState
        currentPhrase = currentLocationPhrase
        startTimeUpdates(timezone: currentLocationWeather.timezone)
    }

    func loadWeather(for savedLocation: SavedLocation) async {
        isShowingDeviceLocation = false
        let key = "\(savedLocation.name)\(savedLocation.latitude)"

        // If we already fetched this location and it's fresh, just show cached data
        if let cached = savedLocationCache[key], !cached.weather.isStale {
            weather = cached.weather
            locationName = savedLocation.name
            locationState = savedLocation.state
            currentPhrase = cached.phrase
            startTimeUpdates(timezone: cached.weather.timezone)
            return
        }

        locationName = savedLocation.name
        locationState = savedLocation.state
        await loadWeather(for: savedLocation.clLocation)

        // Cache the result for next tap
        if let weather {
            savedLocationCache[key] = (weather: weather, phrase: currentPhrase)
        }
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

    /// Auto-refresh when app returns to foreground.
    /// Always fetches fresh data to keep the display current.
    /// Guarded against concurrent calls from rapid foreground transitions.
    func refreshOnForeground() async {
        guard !isRefreshing, let weather else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Clear all caches so everything is fresh
        await weatherService.clearCache()
        savedLocationCache.removeAll()

        if isShowingDeviceLocation {
            await loadWeatherForCurrentLocation()
        } else {
            await loadWeather(for: weather.location)
        }
    }

    // MARK: - Computed Properties

    var displayName: String {
        if !locationState.isEmpty {
            return "\(locationName), \(locationState)"
        }
        return locationName
    }

    var currentLocationDisplayName: String {
        if !currentLocationState.isEmpty {
            return "\(currentLocationName), \(currentLocationState)"
        }
        return currentLocationName
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
