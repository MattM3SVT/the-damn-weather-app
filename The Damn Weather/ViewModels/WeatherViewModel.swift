import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import WeatherShared

// MARK: - Per-page weather state (single source of truth for all weather display)

struct PageWeatherState {
    let weather: WeatherSnapshot
    var phrase: String
    let locationName: String
    let locationState: String
    var currentTime: String

    var displayName: String {
        locationState.isEmpty ? locationName : "\(locationName), \(locationState)"
    }
}

@Observable
final class WeatherViewModel {
    // MARK: - Stored properties (iPad "current page" projection + sidebar)
    // These are synced FROM pageStates whenever the active page changes.
    var weather: WeatherSnapshot?
    var locationName: String = ""
    var locationState: String = ""
    var currentPhrase: String = "Loading the attitude..."
    var isLoading = false
    var error: String?
    var currentTime: String = ""

    // MARK: - Per-page pre-loaded state (single source of truth)
    var pageStates: [String: PageWeatherState] = [:]
    var activePageKey: String = "__currentLocation__"

    // MARK: - Device current location state (for sidebar "My Location" card)
    var currentLocationWeather: WeatherSnapshot?
    var currentLocationName: String = ""
    var currentLocationState: String = ""
    var currentLocationPhrase: String = ""

    // MARK: - Location tracking
    private(set) var isShowingDeviceLocation = false
    private var isRefreshing = false

    // MARK: - Dependencies
    private let weatherService = WeatherService()
    private let locationService: LocationService
    /// Shared phrase engine — also passed to SavedLocationsView/LocationSidebar
    /// so they don't create redundant instances that pollute the seen-phrase tracking.
    let phraseEngine = PhraseEngine()
    private let appState: AppState
    private var timeTimer: Timer?

    /// Manages the widget update Task for city swiping. Cancelled and replaced on each
    /// swipe so only the most recent swipe's data reaches the widget.
    private var widgetUpdateTask: Task<Void, Never>?

    init(locationService: LocationService, appState: AppState) {
        self.locationService = locationService
        self.appState = appState
    }

    // MARK: - Page Key Helpers

    static let currentLocationKey = "__currentLocation__"

    /// Coordinate-based key — stable and unique, matches WeatherService cache key format.
    static func pageKey(lat: Double, lon: Double) -> String {
        String(format: "%.3f,%.3f", lat, lon)
    }

    func pageKey(for location: SavedLocation) -> String {
        Self.pageKey(lat: location.latitude, lon: location.longitude)
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

    func loadWeather(for location: CLLocation, isDeviceLocation: Bool = false, savedName: String? = nil, savedState: String? = nil) async {
        isLoading = true
        error = nil

        // Geocode runs independently — it never throws, so it can never kill weather data
        async let geocodeTask = locationService.reverseGeocode(location)

        do {
            let snapshot = try await weatherService.fetchWeather(for: location)

            // WeatherKit succeeded — use real data
            weather = snapshot

            let geocode = await geocodeTask
            // Use saved name if provided (consistent with what user saved), fall back to geocode
            let displayName = savedName ?? geocode.name
            let displayState = savedState ?? geocode.state
            locationName = displayName
            locationState = displayState

            // If this is the device's current location, save it separately for the sidebar
            if isDeviceLocation {
                currentLocationWeather = snapshot
                currentLocationName = displayName
                currentLocationState = displayState
            }

            // Generate phrase BEFORE storing into pageStates (fixes stale phrase flash).
            // refreshPhrase() is purely in-memory — no widget writes.
            await refreshPhrase()

            // If this is the device location, also save the phrase for the sidebar
            if isDeviceLocation {
                currentLocationPhrase = currentPhrase
            }

            // Now store into pageStates with the CORRECT phrase
            let pageKey = isDeviceLocation ? Self.currentLocationKey : Self.pageKey(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
            let timeStr = Date.currentTimeString(timezone: snapshot.timezone)
            pageStates[pageKey] = PageWeatherState(
                weather: snapshot,
                phrase: currentPhrase,
                locationName: displayName,
                locationState: displayState,
                currentTime: timeStr
            )

            // Only update widget data if this city IS the currently active page.
            // This prevents non-active city loads (prefetch, foreground refresh of
            // GPS location while viewing a saved city) from overwriting widget data.
            if activePageKey == pageKey {
                await updateWidget(for: pageKey)
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
        activePageKey = Self.currentLocationKey
        guard let currentLocationWeather else { return }
        weather = currentLocationWeather
        locationName = currentLocationName
        locationState = currentLocationState
        currentPhrase = currentLocationPhrase
        startTimeUpdates(timezone: currentLocationWeather.timezone)
    }

    func loadWeather(for savedLocation: SavedLocation) async {
        isShowingDeviceLocation = false
        let key = pageKey(for: savedLocation)
        activePageKey = key  // Ensure widget knows which city is active (needed for iPad)

        // If we already have pre-loaded data and it's fresh, sync to stored properties
        if let pageState = pageStates[key], !pageState.weather.isStale {
            weather = pageState.weather
            locationName = savedLocation.name
            locationState = savedLocation.state
            currentPhrase = pageState.phrase
            startTimeUpdates(timezone: pageState.weather.timezone)
            return
        }

        // Otherwise fetch fresh — pass saved name for consistent display
        locationName = savedLocation.name
        locationState = savedLocation.state
        await loadWeather(for: savedLocation.clLocation, savedName: savedLocation.name, savedState: savedLocation.state)
    }

    /// Generate a new phrase for the current weather. Purely in-memory — does NOT
    /// write to widget storage. Callers are responsible for triggering widget updates
    /// via `updateWidget(for:)` when needed.
    func refreshPhrase() async {
        guard let weather else { return }
        currentPhrase = await phraseEngine.selectPhrase(
            conditionTag: weather.current.conditionTag,
            tempF: weather.current.temperature,
            mode: appState.phraseMode,
            isDay: weather.current.isDay
        )
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
    /// NOTE: We intentionally keep pageStates populated during refresh so the user
    /// sees existing (stale) data while fresh data loads — no empty-state flash.
    func refreshOnForeground() async {
        guard !isRefreshing, let weather else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Clear API/lookup caches so next fetch hits the network
        await weatherService.clearCache()
        // DO NOT clear pageStates — keep stale data visible while refreshing

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
        weather?.alerts.isEmpty == false
    }

    var temperatureUnit: TemperatureUnit {
        appState.temperatureUnit
    }

    // MARK: - Time Updates

    /// Updates the time for ALL pages (each city has its own timezone).
    private func startTimeUpdates(timezone: TimeZone) {
        timeTimer?.invalidate()
        updateAllPageTimes()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateAllPageTimes()
        }
    }

    private func updateAllPageTimes() {
        // Only update the active page (visible to user) and the stored property for iPad.
        // Other pages are updated lazily when navigated to via onChange(of: selectedPage).
        if let state = pageStates[activePageKey] {
            pageStates[activePageKey]?.currentTime = Date.currentTimeString(timezone: state.weather.timezone)
        }
        if let tz = weather?.timezone {
            currentTime = Date.currentTimeString(timezone: tz)
        }
    }

    deinit {
        timeTimer?.invalidate()
    }

    // MARK: - Per-Page Pre-fetching (iPhone city swiping)

    /// Pre-fetch weather for all saved cities in parallel so swiping is instant.
    func prefetchAllLocations(_ savedLocations: [SavedLocation]) async {
        await withTaskGroup(of: (String, PageWeatherState?).self) { group in
            for location in savedLocations {
                let key = pageKey(for: location)
                // Skip if we already have fresh data
                if let existing = pageStates[key], !existing.weather.isStale {
                    continue
                }
                group.addTask { [self] in
                    do {
                        let snapshot = try await weatherService.fetchWeather(for: location.clLocation)
                        let phrase = await phraseEngine.selectPhrase(
                            conditionTag: snapshot.current.conditionTag,
                            tempF: snapshot.current.temperature,
                            mode: appState.phraseMode,
                            isDay: snapshot.current.isDay
                        )
                        let timeStr = Date.currentTimeString(timezone: snapshot.timezone)
                        return (key, PageWeatherState(
                            weather: snapshot,
                            phrase: phrase,
                            locationName: location.name,
                            locationState: location.state,
                            currentTime: timeStr
                        ))
                    } catch {
                        #if DEBUG
                        print("🌦️ Prefetch failed for \(location.name): \(error)")
                        #endif
                        return (key, nil)
                    }
                }
            }
            for await (key, state) in group {
                if let state {
                    pageStates[key] = state
                }
            }
        }
    }

    // MARK: - Widget Updates

    /// Called from MainView when user swipes to a new city page.
    /// Cancels any in-flight widget update from a previous swipe so only the
    /// most recent swipe's data reaches the widget. The captured `pageKey` ensures
    /// the correct city is written even if `activePageKey` changes before execution.
    func scheduleWidgetUpdate(for pageKey: String) {
        widgetUpdateTask?.cancel()
        widgetUpdateTask = Task {
            guard !Task.isCancelled else { return }
            await updateWidget(for: pageKey)
            guard !Task.isCancelled else { return }
            await refreshPageIfStale(for: pageKey)
        }
    }

    /// Write complete, consistent widget data for the specified page.
    /// Uses `pageKey` parameter (not `activePageKey`) to avoid stale reads from rapid swipes.
    /// Generates all widget phrases (primary + 3 extra for timeline rotation + small).
    func updateWidget(for pageKey: String) async {
        guard !Task.isCancelled else { return }
        guard let state = pageStates[pageKey] else { return }
        let snapshot = state.weather

        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.set(snapshot.location.coordinate.latitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLat)
        defaults.set(snapshot.location.coordinate.longitude, forKey: AppConstants.UserDefaultsKeys.lastLocationLon)
        defaults.set(state.locationName, forKey: AppConstants.UserDefaultsKeys.lastLocationName)

        // Build hourly/daily preview arrays for the large widget
        let now = Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "ha"
        let cachedHourly: [CachedHourlyPoint] = Array(
            snapshot.hourly.filter { $0.time >= currentHourStart }.prefix(6)
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

        // ── Phase 1: Write JSON + UserDefaults IMMEDIATELY with main phrase ──
        // This ensures the widget has real data right away, even before extra
        // phrase generation (which is slow — loads 728KB JSON on first call).
        WidgetDataStore.save(CachedWeatherData(
            temperature: snapshot.current.temperature,
            conditionTag: snapshot.current.conditionTag.rawValue,
            conditionLabel: snapshot.current.conditionLabel,
            isDay: snapshot.current.isDay,
            feelsLike: snapshot.current.feelsLike,
            high: snapshot.daily.first?.high ?? 0,
            low: snapshot.daily.first?.low ?? 0,
            locationName: state.locationName,
            phrase: state.phrase,
            phraseMode: appState.phraseMode.rawValue,
            hourlyPreview: cachedHourly,
            dailyPreview: cachedDaily
        ))

        // UserDefaults fallback for weather values (widget provider uses these if JSON fails)
        defaults.set(snapshot.current.temperature, forKey: AppConstants.UserDefaultsKeys.cachedTemperature)
        defaults.set(snapshot.current.conditionTag.rawValue, forKey: AppConstants.UserDefaultsKeys.cachedConditionTag)
        defaults.set(snapshot.current.conditionLabel, forKey: AppConstants.UserDefaultsKeys.cachedConditionLabel)
        defaults.set(snapshot.current.isDay, forKey: AppConstants.UserDefaultsKeys.cachedIsDay)
        defaults.set(snapshot.current.feelsLike, forKey: AppConstants.UserDefaultsKeys.cachedFeelsLike)
        defaults.set(snapshot.daily.first?.high ?? 0, forKey: AppConstants.UserDefaultsKeys.cachedHigh)
        defaults.set(snapshot.daily.first?.low ?? 0, forKey: AppConstants.UserDefaultsKeys.cachedLow)
        defaults.set(state.phrase, forKey: AppConstants.UserDefaultsKeys.currentPhrase)
        defaults.set(appState.phraseMode.rawValue, forKey: AppConstants.UserDefaultsKeys.phraseMode)
        defaults.synchronize()

        // Tell WidgetKit to refresh NOW — widget gets real weather data instantly
        WidgetCenter.shared.reloadAllTimelines()

        // ── Phase 2: Generate extra phrases in background, then update JSON ──
        // Additional phrases enable the widget to show variety across 15-min cycles.
        // This is slow (loads PhraseEngine JSON) but the widget already has data above.
        let extraPhrases = await phraseEngine.selectMultiplePhrases(
            count: 3,
            conditionTag: snapshot.current.conditionTag,
            tempF: snapshot.current.temperature,
            mode: appState.phraseMode,
            isDay: snapshot.current.isDay
        )

        let smallPhrase = await phraseEngine.selectPhrase(
            conditionTag: snapshot.current.conditionTag,
            tempF: snapshot.current.temperature,
            mode: appState.phraseMode,
            isDay: snapshot.current.isDay,
            maxLength: 70
        )

        // Bail if this task was superseded by a newer swipe while generating phrases
        guard !Task.isCancelled else { return }

        // Update JSON with the full set of phrases for timeline rotation
        WidgetDataStore.save(CachedWeatherData(
            temperature: snapshot.current.temperature,
            conditionTag: snapshot.current.conditionTag.rawValue,
            conditionLabel: snapshot.current.conditionLabel,
            isDay: snapshot.current.isDay,
            feelsLike: snapshot.current.feelsLike,
            high: snapshot.daily.first?.high ?? 0,
            low: snapshot.daily.first?.low ?? 0,
            locationName: state.locationName,
            phrase: state.phrase,
            phraseMode: appState.phraseMode.rawValue,
            additionalPhrases: extraPhrases,
            smallPhrase: smallPhrase,
            hourlyPreview: cachedHourly,
            dailyPreview: cachedDaily
        ))
        defaults.synchronize()

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// If the specified page's data is stale, refresh it in the background.
    /// The user sees stale data instantly (no lag) and it updates when fresh data arrives.
    /// Uses `pageKey` parameter (not `activePageKey`) to avoid stale reads from rapid swipes.
    func refreshPageIfStale(for pageKey: String) async {
        guard let state = pageStates[pageKey], state.weather.isStale else { return }
        do {
            let snapshot = try await weatherService.fetchWeather(for: state.weather.location)
            let phrase = await phraseEngine.selectPhrase(
                conditionTag: snapshot.current.conditionTag,
                tempF: snapshot.current.temperature,
                mode: appState.phraseMode,
                isDay: snapshot.current.isDay
            )
            pageStates[pageKey] = PageWeatherState(
                weather: snapshot,
                phrase: phrase,
                locationName: state.locationName,
                locationState: state.locationState,
                currentTime: Date.currentTimeString(timezone: snapshot.timezone)
            )
            // Only sync stored properties if this is still the active page
            if activePageKey == pageKey {
                weather = snapshot
                currentPhrase = phrase
            }
            // Push fresh data to widget (replaces stale prefetch data)
            await updateWidget(for: pageKey)
        } catch {
            // Stale data stays visible — better than nothing
        }
    }

    /// Refresh weather for a specific saved location page (pull-to-refresh).
    func refreshPage(for location: SavedLocation) async {
        let key = pageKey(for: location)
        await weatherService.clearCache()
        do {
            let snapshot = try await weatherService.fetchWeather(for: location.clLocation)
            let phrase = await phraseEngine.selectPhrase(
                conditionTag: snapshot.current.conditionTag,
                tempF: snapshot.current.temperature,
                mode: appState.phraseMode,
                isDay: snapshot.current.isDay
            )
            pageStates[key] = PageWeatherState(
                weather: snapshot,
                phrase: phrase,
                locationName: location.name,
                locationState: location.state,
                currentTime: Date.currentTimeString(timezone: snapshot.timezone)
            )
            // Also update the stored properties and widget if this is the active page
            if activePageKey == key {
                weather = snapshot
                locationName = location.name
                locationState = location.state
                currentPhrase = phrase
                // Push refreshed data to widget
                await updateWidget(for: key)
            }
        } catch {
            #if DEBUG
            print("🌦️ Refresh failed for \(location.name): \(error)")
            #endif
        }
    }

    /// Refresh the phrase for a specific page (phrase tap).
    func refreshPhraseForPage(_ key: String) async {
        guard var state = pageStates[key] else { return }
        let newPhrase = await phraseEngine.selectPhrase(
            conditionTag: state.weather.current.conditionTag,
            tempF: state.weather.current.temperature,
            mode: appState.phraseMode,
            isDay: state.weather.current.isDay
        )
        state.phrase = newPhrase
        pageStates[key] = state

        // Keep stored properties and widget in sync if this is the active page
        if activePageKey == key {
            currentPhrase = newPhrase
            // Full widget update — includes new phrase, extra phrases, and smallPhrase
            await updateWidget(for: key)
        }
    }

    /// Refresh all page phrases when phrase mode changes.
    func refreshAllPagePhrases() async {
        for (key, state) in pageStates {
            let newPhrase = await phraseEngine.selectPhrase(
                conditionTag: state.weather.current.conditionTag,
                tempF: state.weather.current.temperature,
                mode: appState.phraseMode,
                isDay: state.weather.current.isDay
            )
            pageStates[key]?.phrase = newPhrase
        }
        // Update stored property for active page
        if let activeState = pageStates[activePageKey] {
            currentPhrase = activeState.phrase
        }
    }
}
