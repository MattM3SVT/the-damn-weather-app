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

            // Save location + weather snapshot to shared container for widgets
            let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
            defaults.set(location.coordinate.latitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLat)
            defaults.set(location.coordinate.longitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLon)
            defaults.set(geocode.name, forKey: AppConstants.UserDefaultsKeys.lastLocationName)

            // Build hourly/daily preview arrays for the large widget
            let now = Date()
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "ha"   // "3PM"
            let cachedHourly: [CachedHourlyPoint] = Array(
                snapshot.hourly.filter { $0.time >= now }.prefix(6)
            ).enumerated().map { index, h in
                CachedHourlyPoint(
                    hour: index == 0 ? "Now" : hourFormatter.string(from: h.time).replacingOccurrences(of: " ", with: ""),
                    temp: Int(h.temperature.rounded()),
                    conditionTag: h.conditionTag.rawValue,
                    isDay: h.isDay
                )
            }
            let cachedDaily: [CachedDailyPoint] = Array(
                snapshot.daily.prefix(5)
            ).enumerated().map { index, d in
                let dayStr: String
                if index == 0 {
                    dayStr = "Today"
                } else {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "EEE"
                    dayStr = fmt.string(from: d.date)
                }
                return CachedDailyPoint(
                    day: dayStr,
                    high: Int(d.high.rounded()),
                    low: Int(d.low.rounded()),
                    conditionTag: d.conditionTag.rawValue
                )
            }

            // Generate a short phrase for the small widget (≤70 chars)
            let smallPhrase = await phraseEngine.selectPhrase(
                conditionTag: snapshot.current.conditionTag,
                tempF: snapshot.current.temperature,
                mode: appState.phraseMode,
                isDay: snapshot.current.isDay,
                maxLength: 70
            )

            // Write to shared JSON file (reliable cross-process, used by widget)
            WidgetDataStore.save(CachedWeatherData(
                temperature: snapshot.current.temperature,
                conditionTag: snapshot.current.conditionTag.rawValue,
                conditionLabel: snapshot.current.conditionLabel,
                isDay: snapshot.current.isDay,
                feelsLike: snapshot.current.feelsLike,
                high: snapshot.daily.first?.high ?? 0,
                low: snapshot.daily.first?.low ?? 0,
                locationName: geocode.name,
                phrase: currentPhrase,
                phraseMode: appState.phraseMode.rawValue,
                smallPhrase: smallPhrase,
                hourlyPreview: cachedHourly,
                dailyPreview: cachedDaily
            ))

            // Also write to UserDefaults as fallback
            defaults.set(snapshot.current.temperature, forKey: AppConstants.UserDefaultsKeys.cachedTemperature)
            defaults.set(snapshot.current.conditionTag.rawValue, forKey: AppConstants.UserDefaultsKeys.cachedConditionTag)
            defaults.set(snapshot.current.conditionLabel, forKey: AppConstants.UserDefaultsKeys.cachedConditionLabel)
            defaults.set(snapshot.current.isDay, forKey: AppConstants.UserDefaultsKeys.cachedIsDay)
            defaults.set(snapshot.current.feelsLike, forKey: AppConstants.UserDefaultsKeys.cachedFeelsLike)
            defaults.set(snapshot.daily.first?.high ?? 0, forKey: AppConstants.UserDefaultsKeys.cachedHigh)
            defaults.set(snapshot.daily.first?.low ?? 0, forKey: AppConstants.UserDefaultsKeys.cachedLow)
            defaults.synchronize()

            // Trigger widget reload immediately so it picks up the new location
            WidgetCenter.shared.reloadAllTimelines()

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

        // Generate the primary phrase for the app display
        currentPhrase = await phraseEngine.selectPhrase(
            conditionTag: weather.current.conditionTag,
            tempF: weather.current.temperature,
            mode: appState.phraseMode,
            isDay: weather.current.isDay
        )

        // Pre-generate 3 additional phrases for the widget's multi-entry timeline.
        // The widget shows a different phrase every 15 minutes without needing
        // to run PhraseEngine in the extension (which can be killed by WidgetKit).
        let extraPhrases = await phraseEngine.selectMultiplePhrases(
            count: 3,
            conditionTag: weather.current.conditionTag,
            tempF: weather.current.temperature,
            mode: appState.phraseMode,
            isDay: weather.current.isDay
        )

        // Generate a short phrase for the small widget (≤70 chars)
        let smallPhrase = await phraseEngine.selectPhrase(
            conditionTag: weather.current.conditionTag,
            tempF: weather.current.temperature,
            mode: appState.phraseMode,
            isDay: weather.current.isDay,
            maxLength: 70
        )

        // Share phrases with the widget and trigger refresh
        WidgetDataStore.updatePhrase(
            currentPhrase,
            mode: appState.phraseMode.rawValue,
            additionalPhrases: extraPhrases,
            smallPhrase: smallPhrase
        )
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.set(currentPhrase, forKey: AppConstants.UserDefaultsKeys.currentPhrase)
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
