import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import WeatherKit
import WeatherShared
import os.log

nonisolated private let vmLog = Logger(subsystem: "DamnWeather", category: "WeatherViewModel")

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
    var weatherAttribution: WeatherAttribution?

    // MARK: - Per-page pre-loaded state (single source of truth)
    var pageStates: [String: PageWeatherState] = [:]
    var activePageKey: String = "__currentLocation__"

    /// Maps the in-memory `pageKey` (coordinate-based) to the `SavedLocation.uuid`
    /// used as the widget cache key. Kept in sync by `MainView` on every change
    /// to the saved-locations list so `updateWidget(for:)` can route weather
    /// into the right per-location entry in the App Group multi-cache.
    var savedLocationUUIDs: [String: String] = [:]

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
    /// Backed by the App Group defaults so the app and the widget share one
    /// seen/last-shown domain (the widget's engine already lives there).
    let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )
    private let appState: AppState
    /// Tracks engagement signals (successful non-partial fetch count, days
    /// since install, "have we already asked") so MainView can decide when
    /// to call the OS `requestReview()` prompt at most one time, ever.
    private let reviewPrompt: ReviewPromptCoordinator
    private var timeTimer: Timer?

    init(locationService: LocationService, appState: AppState, reviewPrompt: ReviewPromptCoordinator) {
        self.locationService = locationService
        self.appState = appState
        self.reviewPrompt = reviewPrompt
        // Warm the phrase JSON in parallel with hydration / network fetch so
        // the first `refreshPhrase()` after a fresh WeatherKit response doesn't
        // pay the ~728KB decode cost serially. The actor's loadIfNeeded() is
        // idempotent, so the eventual selectPhrase call is a no-op if this
        // already finished.
        Task.detached(priority: .utility) { [phraseEngine] in
            await phraseEngine.warmUp()
        }
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

    /// Populate `pageStates` from the widget's persistent App Group cache so
    /// cold-launch renders real data instantly instead of a skeleton. The
    /// cached snapshots are marked `isPartial` — HeroSection hides Wind/UV
    /// Index and WeatherView hides the detail grid until a fresh fetch lands.
    ///
    /// Requires `savedLocationUUIDs` to already be synced (MainView does this
    /// before calling us). Safe to call repeatedly — skips keys that already
    /// have a non-partial pageState populated.
    func hydrateFromWidgetCache(savedLocations: [SavedLocation]) {
        var multi = WidgetDataStore.loadMulti()

        // Fall back to the legacy single-entry cache for the My Location slot
        // when the multi-cache is missing. `updateWidget` still maintains both
        // files, so users coming from a pre-multi-cache build (or whose multi
        // file was wiped) still get a non-empty hero on cold launch.
        if multi[LocationEntity.myLocationID] == nil,
           let legacy = WidgetDataStore.load() {
            multi[LocationEntity.myLocationID] = legacy
            vmLog.info("hydrate: multi missing My Location; using legacy single-entry cache")
        }

        guard !multi.isEmpty else {
            vmLog.info("hydrate: cache empty — nothing to hydrate (saved=\(savedLocations.count))")
            return
        }

        let hasMyLocation = multi[LocationEntity.myLocationID] != nil
        let savedHits = savedLocations.filter { multi[$0.uuid] != nil }.count
        vmLog.info("hydrate: multi=\(multi.count) entries, myLocation=\(hasMyLocation), savedHits=\(savedHits)/\(savedLocations.count), activeKey=\(self.activePageKey, privacy: .public)")

        // Pages whose cached phrase was generated for the other half of the
        // day (cache written in daylight, launched after dark, or vice
        // versa). Their phrases are regenerated asynchronously below so a
        // "sun's blasting" line never greets a 9 PM cold launch.
        var phraseFixups: [(key: String, tag: WeatherConditionTag, temp: Double, isDay: Bool)] = []

        // My Location entry — use a placeholder CLLocation(0,0); `refresh()`
        // and `refreshOnForeground()` route through `loadWeatherForCurrentLocation()`
        // when `isShowingDeviceLocation` is true, so the placeholder coord is
        // never used for a real fetch.
        if let cached = multi[LocationEntity.myLocationID],
           pageStates[Self.currentLocationKey]?.weather.isPartial != false {
            let snapshot = Self.syntheticSnapshot(
                from: cached,
                location: CLLocation(latitude: 0, longitude: 0)
            )
            let (name, state) = Self.splitCachedLocationName(cached.locationName)
            pageStates[Self.currentLocationKey] = PageWeatherState(
                weather: snapshot,
                phrase: cached.phrase,
                locationName: name,
                locationState: state,
                currentTime: Date.currentTimeString(timezone: snapshot.timezone)
            )
            // Seed the sidebar's device-location projection too so the iPad
            // sidebar and the "My Location" chip aren't blank on first render.
            currentLocationWeather = snapshot
            currentLocationName = name
            currentLocationState = state
            currentLocationPhrase = cached.phrase
            // Mark the device-location path so `refresh()` routes through
            // `loadWeatherForCurrentLocation()` if a pull-to-refresh fires
            // before the initial fetch sets this flag itself.
            isShowingDeviceLocation = true
            // Seed the iPad stored-property projection for the active page.
            if activePageKey == Self.currentLocationKey {
                weather = snapshot
                locationName = name
                locationState = state
                currentPhrase = cached.phrase
            }
            vmLog.info("hydrate: filled My Location — temp=\(cached.temperature), phrase=\"\(cached.phrase.prefix(40), privacy: .public)\"")
            if snapshot.current.isDay != cached.isDay {
                phraseFixups.append((
                    key: Self.currentLocationKey,
                    tag: snapshot.current.conditionTag,
                    temp: snapshot.current.temperature,
                    isDay: snapshot.current.isDay
                ))
            }
        }

        // Saved cities — we have real coords, so synthetic snapshots can carry
        // the correct `location` and refresh paths work normally.
        var filledSaved = 0
        var skippedFresh = 0
        for saved in savedLocations {
            guard let cached = multi[saved.uuid] else { continue }
            let key = pageKey(for: saved)
            // Skip if a real (non-partial) snapshot is already loaded
            if let existing = pageStates[key], !existing.weather.isPartial {
                skippedFresh += 1
                continue
            }
            let snapshot = Self.syntheticSnapshot(
                from: cached,
                location: saved.clLocation
            )
            pageStates[key] = PageWeatherState(
                weather: snapshot,
                phrase: cached.phrase,
                locationName: saved.name,
                locationState: saved.state,
                currentTime: Date.currentTimeString(timezone: snapshot.timezone)
            )
            filledSaved += 1
            if snapshot.current.isDay != cached.isDay {
                phraseFixups.append((
                    key: key,
                    tag: snapshot.current.conditionTag,
                    temp: snapshot.current.temperature,
                    isDay: snapshot.current.isDay
                ))
            }
        }
        if filledSaved > 0 || skippedFresh > 0 {
            vmLog.info("hydrate: saved cities — filled=\(filledSaved), skippedFresh=\(skippedFresh)")
        }

        // Regenerate mismatched phrases once the engine is warm. Applied only
        // while the page is still showing the hydrated partial — a fresh
        // fetch that lands first wins and this becomes a no-op.
        if !phraseFixups.isEmpty {
            vmLog.info("hydrate: regenerating \(phraseFixups.count) phrase(s) whose day/night no longer matches")
            Task {
                for fixup in phraseFixups {
                    let phrase = await phraseEngine.selectPhrase(
                        conditionTag: fixup.tag,
                        tempF: fixup.temp,
                        mode: appState.phraseMode,
                        isDay: fixup.isDay,
                        localHour: pageStates[fixup.key].map { Date().localHour(timezone: $0.weather.timezone) },
                        localMonthDay: pageStates[fixup.key].map { Date().localMonthDay(timezone: $0.weather.timezone) },
                        trackAsSeen: false
                    )
                    guard pageStates[fixup.key]?.weather.isPartial == true else { continue }
                    pageStates[fixup.key]?.phrase = phrase
                    if fixup.key == Self.currentLocationKey { currentLocationPhrase = phrase }
                    if activePageKey == fixup.key { currentPhrase = phrase }
                }
            }
        }
    }

    /// Build a minimal but renderable `WeatherSnapshot` from a widget cache
    /// entry. Detail fields (pressure, wind, UV, visibility, cloud cover,
    /// humidity, dew point) are zeroed; `isPartial = true` signals to the
    /// views to hide widgets that would render those zeros.
    /// Best-available "current" reading from a cache record. When the cache
    /// was written in an earlier hour, prefer the hourly forecast slot
    /// covering now — its temp/condition/isDaylight keep a stale hydration
    /// honest (a cache written at 3 PM shouldn't paint a daytime hero, a
    /// daytime phrase, and an afternoon temperature at 9 PM).
    private static func derivedCurrent(
        from cached: CachedWeatherData
    ) -> (temp: Double, tag: WeatherConditionTag, label: String, isDay: Bool) {
        let cachedTag = WeatherConditionTag(rawValue: cached.conditionTag) ?? .clear
        let fallback = (cached.temperature, cachedTag, cached.conditionLabel, cached.isDay)
        let now = Date()
        if Calendar.current.isDate(cached.updatedAt, equalTo: now, toGranularity: .hour) {
            return fallback
        }
        guard let slot = cached.hourlyPreview
                .filter({ $0.date != nil })
                .last(where: { $0.date! <= now }),
              let slotTag = WeatherConditionTag(rawValue: slot.conditionTag) else {
            return fallback
        }
        return (Double(slot.temp), slotTag, slotTag.label, slot.isDay)
    }

    private static func syntheticSnapshot(
        from cached: CachedWeatherData,
        location: CLLocation
    ) -> WeatherSnapshot {
        let derived = derivedCurrent(from: cached)
        let conditionTag = derived.tag
        let current = CurrentWeatherData(
            temperature: derived.temp,
            feelsLike: derived.temp == cached.temperature ? cached.feelsLike : derived.temp,
            humidity: 0,
            isDay: derived.isDay,
            precipitation: 0,
            conditionTag: conditionTag,
            conditionLabel: derived.label,
            pressure: 0,
            windSpeed: 0,
            windDirection: 0,
            windGusts: 0,
            cloudCover: 0,
            uvIndex: 0,
            visibility: 0,
            dewPoint: 0
        )

        // Expand cached preview points to the app's richer forecast types.
        // The hourly strip renders temp + condition + isDay only; the daily
        // strip renders high/low + condition only. Zeros are invisible.
        let now = Date()
        let calendar = Calendar.current
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let hourly = cached.hourlyPreview.enumerated().map { index, h -> HourlyForecastPoint in
            let time = calendar.date(byAdding: .hour, value: index, to: currentHourStart) ?? now
            return HourlyForecastPoint(
                time: time,
                temperature: Double(h.temp),
                feelsLike: Double(h.temp),
                precipitationProbability: 0,
                conditionTag: WeatherConditionTag(rawValue: h.conditionTag) ?? .clear,
                windSpeed: 0,
                windDirection: 0,
                windGusts: 0,
                isDay: h.isDay,
                humidity: 0,
                pressure: 0,
                visibility: 0,
                uvIndex: 0,
                dewPoint: 0,
                cloudCover: 0,
                precipitationAmount: 0
            )
        }
        let startOfDay = calendar.startOfDay(for: now)
        let daily = cached.dailyPreview.enumerated().map { index, d -> DailyForecastPoint in
            let date = calendar.date(byAdding: .day, value: index, to: startOfDay) ?? now
            return DailyForecastPoint(
                date: date,
                high: Double(d.high),
                low: Double(d.low),
                conditionTag: WeatherConditionTag(rawValue: d.conditionTag) ?? .clear,
                conditionLabel: "",
                sunrise: date,
                sunset: date,
                precipitationSum: 0,
                precipitationProbability: 0,
                windMax: 0,
                uvIndexMax: 0,
                moonPhase: nil,
                moonIllumination: 0
            )
        }

        // AQI is only restored while the observation is recent. A reading
        // from last night's fireworks spike replayed the next morning would
        // be worse than showing nothing until the live fetch lands.
        let carriedAQI = cached.airQuality.flatMap { aqi in
            Date().timeIntervalSince(aqi.observedAt) <= AppConstants.airQualityMaxCarryAge ? aqi : nil
        }

        return WeatherSnapshot(
            current: current,
            hourly: hourly,
            daily: daily,
            minutePrecipitation: [],
            alerts: [],
            moonPhase: nil,
            timezone: cached.timezoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current,
            fetchedAt: cached.updatedAt,
            location: location,
            airQuality: carriedAQI,
            isPartial: true
        )
    }

    /// Cache stores a combined display name like "Seattle, WA" — split back
    /// into (name, state) so the view model's projections match the fresh
    /// fetch shape (which keeps them separate).
    private static func splitCachedLocationName(_ combined: String) -> (name: String, state: String) {
        let parts = combined.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (combined, "")
    }

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

            // Fetch attribution once (same for all locations)
            if weatherAttribution == nil {
                weatherAttribution = await weatherService.fetchAttribution()
            }

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
                Self.persistLastKnownLocation(location)
                await ForecastNotificationService.shared.scheduleFromSnapshot(snapshot)
                await RainActivityManager.shared.reconcile(with: snapshot, locationName: displayName)
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

            // For saved cities, only update widget data when this city IS the
            // active page — prevents a prefetch of city X from overwriting
            // city Y's widget cache. For the device's current location there
            // is only one cache entry (`__myLocation__`), so always refresh
            // it when device-location data lands; otherwise a user who left
            // the app on a saved city would never see their My Location
            // widget recover from a stale state.
            if isDeviceLocation || activePageKey == pageKey {
                await updateWidget(for: pageKey)
            }

            // Start time updates
            startTimeUpdates(timezone: snapshot.timezone)

            isLoading = false

            // Engagement signal for the review prompt — counted only on
            // non-partial loads (the user just saw real, full weather), and
            // capped/no-op once we've already prompted.
            if !snapshot.isPartial {
                reviewPrompt.recordSuccessfulFetch()
            }
        } catch {
            let errorDesc = String(describing: error)
            vmLog.error("WeatherKit error: \(errorDesc, privacy: .public)")

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
            isDay: weather.current.isDay,
            localHour: Date().localHour(timezone: weather.timezone),
                localMonthDay: Date().localMonthDay(timezone: weather.timezone)
        )
    }

    func refresh() async {
        guard let weather else {
            await loadWeatherForCurrentLocation()
            return
        }
        await weatherService.clearCache()
        // When the active page is the device's current location, refresh via
        // GPS — the snapshot's `location` may be a placeholder (e.g. when the
        // snapshot was hydrated from the widget cache, which stores no coords
        // for My Location).
        if isShowingDeviceLocation {
            await loadWeatherForCurrentLocation()
        } else {
            await loadWeather(for: weather.location)
        }
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
            // User is on a saved-city page. Refresh that city for the visible
            // UI, AND silently refresh device location so the My Location
            // widget cache doesn't go stale just because the user happens to
            // be viewing a different city.
            await loadWeather(for: weather.location)
            await refreshDeviceLocationCacheSilently()
        }
    }

    /// Fetch device-location weather and persist to the widget cache for
    /// `myLocationID`, without touching `isShowingDeviceLocation`,
    /// `activePageKey`, `weather`, or `isLoading`. Used at foreground when
    /// the user is on a saved-city page so a widget configured for My
    /// Location still gets refreshed. Silent on failure — the existing
    /// cached entry is left alone.
    private func refreshDeviceLocationCacheSilently() async {
        let auth = locationService.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else { return }

        do {
            let location = try await locationService.requestLocation()
            let snapshot = try await weatherService.fetchWeather(for: location)
            let geocode = await locationService.reverseGeocode(location)
            let displayName = geocode.name.isEmpty ? "Current Location" : geocode.name
            let phrase = await phraseEngine.selectPhrase(
                conditionTag: snapshot.current.conditionTag,
                tempF: snapshot.current.temperature,
                mode: appState.phraseMode,
                isDay: snapshot.current.isDay,
                localHour: Date().localHour(timezone: snapshot.timezone),
                localMonthDay: Date().localMonthDay(timezone: snapshot.timezone)
            )

            // Update sidebar projections (iPad sidebar reads these); these
            // don't change which page is active.
            currentLocationWeather = snapshot
            currentLocationName = displayName
            currentLocationState = geocode.state
            currentLocationPhrase = phrase

            // Populate pageStates[currentLocationKey] so updateWidget can
            // build a CachedWeatherData from it.
            pageStates[Self.currentLocationKey] = PageWeatherState(
                weather: snapshot,
                phrase: phrase,
                locationName: displayName,
                locationState: geocode.state,
                currentTime: Date.currentTimeString(timezone: snapshot.timezone)
            )

            await updateWidget(for: Self.currentLocationKey)
            Self.persistLastKnownLocation(location)
            await ForecastNotificationService.shared.scheduleFromSnapshot(snapshot)
            await RainActivityManager.shared.reconcile(with: snapshot, locationName: displayName)
        } catch {
            vmLog.error("silent device-location refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Store the last good device fix in the App Group so the morning
    /// forecast's background task (which has no GPS access) knows where to
    /// fetch weather for.
    private static func persistLastKnownLocation(_ location: CLLocation) {
        let group = UserDefaults(suiteName: AppConstants.appGroupID)
        group?.set(location.coordinate.latitude, forKey: AppConstants.UserDefaultsKeys.lastKnownLatitude)
        group?.set(location.coordinate.longitude, forKey: AppConstants.UserDefaultsKeys.lastKnownLongitude)
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

        // An app left open (iPad on a stand, iPhone on a desk) never crosses
        // a scenePhase boundary, so without this the visible snapshot — temp,
        // phrase, isDay, background gradient — freezes at fetch time and
        // sails straight through sunset. Piggyback on the 60s clock tick:
        // once the active snapshot exceeds the cache TTL, refresh it.
        // Partial snapshots are excluded (cold-launch hydration already has
        // a fetch in flight for those).
        if let state = pageStates[activePageKey],
           state.weather.isStale,
           !state.weather.isPartial,
           !isRefreshing,
           !isLoading {
            Task { await refreshOnForeground() }
        }
    }

    deinit {
        timeTimer?.invalidate()
    }

    // MARK: - Per-Page Pre-fetching (iPhone city swiping)

    /// Maximum simultaneous WeatherKit fetches during prefetch. Caps the
    /// burst when a user has many saved cities — Apple throttles parallel
    /// WeatherKit requests, and staggering avoids quota spikes in the
    /// 500k/month per-account budget.
    private static let prefetchConcurrencyLimit = 4

    private struct PrefetchResult {
        let pageKey: String
        let widgetID: String
        let displayName: String
        let state: PageWeatherState
    }

    /// Fetch weather + phrase for a single saved city. Returns nil if the
    /// WeatherKit call fails (error is logged; caller treats as skipped).
    private func prefetchOne(_ location: SavedLocation) async -> PrefetchResult? {
        do {
            let snapshot = try await weatherService.fetchWeather(for: location.clLocation)
            let phrase = await phraseEngine.selectPhrase(
                conditionTag: snapshot.current.conditionTag,
                tempF: snapshot.current.temperature,
                mode: appState.phraseMode,
                isDay: snapshot.current.isDay,
                localHour: Date().localHour(timezone: snapshot.timezone),
                localMonthDay: Date().localMonthDay(timezone: snapshot.timezone)
            )
            let timeStr = Date.currentTimeString(timezone: snapshot.timezone)
            return PrefetchResult(
                pageKey: pageKey(for: location),
                widgetID: location.uuid,
                displayName: location.displayName,
                state: PageWeatherState(
                    weather: snapshot,
                    phrase: phrase,
                    locationName: location.name,
                    locationState: location.state,
                    currentTime: timeStr
                )
            )
        } catch {
            vmLog.error("prefetch failed for \(location.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Pre-fetch weather for all saved cities (concurrency-capped) so swiping
    /// is instant. Also persists each result to the App Group's multi-location
    /// widget cache so widgets configured for any saved city can serve that
    /// city's weather without hitting WeatherKit on every 15-min refresh.
    func prefetchAllLocations(_ savedLocations: [SavedLocation]) async {

        // Filter work items up-front so the task group only handles actual
        // fetches — keeps the concurrency gate accurate. A hydrated partial
        // snapshot has a recent `fetchedAt` from the widget cache but zeroed
        // detail fields (wind, UV, etc.), so it must NOT count as fresh —
        // otherwise saved cities would render the partial render forever
        // because hydration always runs before prefetch on cold launch.
        let work: [SavedLocation] = savedLocations.filter { location in
            let key = pageKey(for: location)
            let cachedEntry = WidgetDataStore.loadEntry(for: location.uuid)
            let cacheStale = cachedEntry.map {
                Date().timeIntervalSince($0.updatedAt) > AppConstants.weatherCacheTTL
            } ?? true
            if let existing = pageStates[key],
               !existing.weather.isPartial,
               !existing.weather.isStale,
               !cacheStale {
                return false
            }
            return true
        }

        var results: [PrefetchResult] = []

        await withTaskGroup(of: PrefetchResult?.self) { group in
            var started = 0
            // Prime the group with up to N tasks; each completion starts the
            // next one so we never have more than N in flight.
            for location in work.prefix(Self.prefetchConcurrencyLimit) {
                group.addTask { [self] in await prefetchOne(location) }
                started += 1
            }
            while let next = await group.next() {
                if let r = next { results.append(r) }
                if started < work.count {
                    let location = work[started]
                    started += 1
                    group.addTask { [self] in await prefetchOne(location) }
                }
            }
        }

        // Commit in-memory state for the active-page / iPad display path.
        for r in results {
            pageStates[r.pageKey] = r.state
        }

        // Commit widget multi-cache. One JSON write for the whole batch.
        if !results.isEmpty {
            var multi = WidgetDataStore.loadMulti()
            for r in results {
                multi[r.widgetID] = await buildCachedWeatherData(
                    from: r.state,
                    displayName: r.displayName
                )
            }
            WidgetDataStore.saveMulti(multi)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Build a `CachedWeatherData` from a loaded `PageWeatherState` WITHOUT
    /// generating extra/small phrases (those require the PhraseEngine's slow
    /// first-load). Used directly for the fast Phase-1 widget write and as
    /// the base for `buildCachedWeatherData`.
    private func makeCachedWeatherData(
        from state: PageWeatherState,
        displayName: String,
        phraseOverride: String? = nil,
        additionalPhrases: [String] = [],
        smallPhrase: String? = nil,
        tinyPhrase: String? = nil
    ) -> CachedWeatherData {
        let snapshot = state.weather
        let now = Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let hourFormatter = Self.hourFormatter(for: snapshot.timezone)
        let dayFormatter = Self.dayFormatter(for: snapshot.timezone)

        let cachedHourly: [CachedHourlyPoint] = Array(
            snapshot.hourly.filter { $0.time >= currentHourStart }.prefix(6)
        ).enumerated().map { index, h in
            CachedHourlyPoint(
                hour: index == 0 ? "Now" : hourFormatter.string(from: h.time).replacingOccurrences(of: " ", with: ""),
                temp: Int(h.temperature.rounded()),
                conditionTag: h.conditionTag.rawValue,
                isDay: h.isDay,
                date: h.time
            )
        }
        let cachedDaily: [CachedDailyPoint] = Array(snapshot.daily.prefix(5)).enumerated().map { index, d in
            CachedDailyPoint(
                day: index == 0 ? "Today" : dayFormatter.string(from: d.date),
                high: Int(d.high.rounded()),
                low: Int(d.low.rounded()),
                conditionTag: d.conditionTag.rawValue
            )
        }

        return CachedWeatherData(
            temperature: snapshot.current.temperature,
            conditionTag: snapshot.current.conditionTag.rawValue,
            conditionLabel: snapshot.current.conditionLabel,
            isDay: snapshot.current.isDay,
            feelsLike: snapshot.current.feelsLike,
            high: snapshot.daily.first?.high ?? 0,
            low: snapshot.daily.first?.low ?? 0,
            locationName: displayName,
            phrase: phraseOverride ?? state.phrase,
            phraseMode: appState.effectiveWidgetPhraseMode.rawValue,
            additionalPhrases: additionalPhrases,
            smallPhrase: smallPhrase,
            tinyPhrase: tinyPhrase,
            hourlyPreview: cachedHourly,
            dailyPreview: cachedDaily,
            timezoneIdentifier: snapshot.timezone.identifier,
            airQuality: snapshot.airQuality
        )
    }

    /// Build a complete `CachedWeatherData`, including the large widget's
    /// hourly/daily preview arrays and a small/primary/extra phrase set.
    /// Shared between the single-location `updateWidget` and the
    /// multi-location `prefetchAllLocations` paths so both produce identical
    /// widget-visible shapes.
    private func buildCachedWeatherData(
        from state: PageWeatherState,
        displayName: String
    ) async -> CachedWeatherData {
        let snapshot = state.weather
        let localHour = Date().localHour(timezone: snapshot.timezone)
        let localMonthDay = Date().localMonthDay(timezone: snapshot.timezone)
        let widgetMode = appState.effectiveWidgetPhraseMode
        let extraPhrases = await phraseEngine.selectMultiplePhrases(
            count: 3,
            conditionTag: snapshot.current.conditionTag,
            tempF: snapshot.current.temperature,
            mode: widgetMode,
            isDay: snapshot.current.isDay,
            localHour: localHour,
            localMonthDay: localMonthDay
        )
        let smallPhrase = await phraseEngine.selectPhrase(
            conditionTag: snapshot.current.conditionTag,
            tempF: snapshot.current.temperature,
            mode: widgetMode,
            isDay: snapshot.current.isDay,
            localHour: localHour,
            localMonthDay: localMonthDay,
            maxLength: 70
        )
        let tinyPhrase = await phraseEngine.selectPhrase(
            conditionTag: snapshot.current.conditionTag,
            tempF: snapshot.current.temperature,
            mode: widgetMode,
            isDay: snapshot.current.isDay,
            localHour: localHour,
            localMonthDay: localMonthDay,
            maxLength: AppConstants.accessoryPhraseMaxLength,
            trackAsSeen: false
        )
        return makeCachedWeatherData(
            from: state,
            displayName: displayName,
            phraseOverride: await widgetPhraseOverride(for: state, localHour: localHour, localMonthDay: localMonthDay),
            additionalPhrases: extraPhrases,
            smallPhrase: smallPhrase,
            tinyPhrase: tinyPhrase
        )
    }

    /// The widget cache's primary phrase is normally the one on screen
    /// (`state.phrase`). When "keep widgets clean" forces a different mode
    /// than the in-app one, generate a widget-only replacement instead.
    private func widgetPhraseOverride(for state: PageWeatherState, localHour: Int?, localMonthDay: String?) async -> String? {
        guard appState.effectiveWidgetPhraseMode != appState.phraseMode else { return nil }
        return await phraseEngine.selectPhrase(
            conditionTag: state.weather.current.conditionTag,
            tempF: state.weather.current.temperature,
            mode: appState.effectiveWidgetPhraseMode,
            isDay: state.weather.current.isDay,
            localHour: localHour,
            localMonthDay: localMonthDay,
            trackAsSeen: false
        )
    }

    // MARK: - Widget Updates
    //
    // As of the per-widget-location rewrite, widgets no longer follow the
    // app's active page — each widget is configured for its own location via
    // AppIntentConfiguration. `updateWidget(for:)` below is still called when
    // weather or phrase data for a given page changes, and it routes that
    // data into the App Group multi-cache keyed by the corresponding
    // `LocationEntity.id` so the widget can find it.

    /// Write complete, consistent widget data for the specified page.
    /// Uses `pageKey` parameter (not `activePageKey`) to avoid stale reads from rapid swipes.
    /// Generates all widget phrases (primary + 3 extra for timeline rotation + small).
    ///
    /// Writes to:
    /// - The App Group multi-cache (keyed by `LocationEntity.id`) — the
    ///   primary source every widget reads.
    /// - The legacy single-file `widget-weather.json` — only when this page IS
    ///   My Location. Kept as a fallback for a widget that still has My
    ///   Location configured but whose multi-cache entry was evicted.
    /// - The `phraseMode` UserDefault — so a widget fetching fresh on cache
    ///   miss generates phrases in the current mode.
    func updateWidget(for pageKey: String) async {
        guard !Task.isCancelled else { return }
        guard let state = pageStates[pageKey] else { return }

        let entityID = widgetEntityID(for: pageKey)
        let isMyLocationPage = (pageKey == Self.currentLocationKey)
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard

        // ── Phase 1: Write multi-cache + single-file IMMEDIATELY with main phrase ──
        // Ensures the widget has real data right away, even before extra
        // phrase generation (slow — PhraseEngine loads 728KB JSON on first call).
        // `state.displayName` includes the state suffix ("Seattle, WA"),
        // matching what `prefetchAllLocations` and the widget's own fresh
        // fetch write for the same entry.
        let partialCached = makeCachedWeatherData(
            from: state,
            displayName: state.displayName,
            phraseOverride: await widgetPhraseOverride(
                for: state,
                localHour: Date().localHour(timezone: state.weather.timezone),
                localMonthDay: Date().localMonthDay(timezone: state.weather.timezone)
            )
        )
        WidgetDataStore.saveEntry(partialCached, for: entityID)
        if isMyLocationPage {
            WidgetDataStore.save(partialCached)
        }
        // phraseMode is the only UserDefault the widget extension reads — its
        // PhraseEngine uses it to generate fresh phrases on cache miss.
        defaults.set(appState.effectiveWidgetPhraseMode.rawValue, forKey: AppConstants.UserDefaultsKeys.phraseMode)

        // Tell WidgetKit to refresh NOW — widget gets real weather data instantly
        WidgetCenter.shared.reloadAllTimelines()

        // ── Phase 2: Generate extra phrases in background, then update cache ──
        // Additional phrases enable the widget to show variety across 15-min cycles.
        // This is slow (loads PhraseEngine JSON) but the widget already has data above.
        let fullCached = await buildCachedWeatherData(from: state, displayName: state.displayName)

        // Bail if this task was superseded by a newer swipe while generating phrases
        guard !Task.isCancelled else { return }

        WidgetDataStore.saveEntry(fullCached, for: entityID)
        if isMyLocationPage {
            WidgetDataStore.save(fullCached)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Resolve a `pageKey` (current-location sentinel OR coordinate-string for
    /// a saved city) into the widget multi-cache key. For coord-based keys we
    /// look up `savedLocationUUIDs` maintained by `MainView`; if unmapped,
    /// fall back to the pageKey itself so data still lands somewhere.
    private func widgetEntityID(for pageKey: String) -> String {
        if pageKey == Self.currentLocationKey {
            return LocationEntity.myLocationID
        }
        return savedLocationUUIDs[pageKey] ?? pageKey
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
                isDay: snapshot.current.isDay,
                localHour: Date().localHour(timezone: snapshot.timezone),
                localMonthDay: Date().localMonthDay(timezone: snapshot.timezone)
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
                isDay: snapshot.current.isDay,
                localHour: Date().localHour(timezone: snapshot.timezone),
                localMonthDay: Date().localMonthDay(timezone: snapshot.timezone)
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
            vmLog.error("refresh failed for \(location.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refresh the phrase for a specific page (phrase tap).
    func refreshPhraseForPage(_ key: String) async {
        guard var state = pageStates[key] else { return }
        let newPhrase = await phraseEngine.selectPhrase(
            conditionTag: state.weather.current.conditionTag,
            tempF: state.weather.current.temperature,
            mode: appState.phraseMode,
            isDay: state.weather.current.isDay,
            localHour: Date().localHour(timezone: state.weather.timezone),
                localMonthDay: Date().localMonthDay(timezone: state.weather.timezone)
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
                isDay: state.weather.current.isDay,
                localHour: Date().localHour(timezone: state.weather.timezone),
                localMonthDay: Date().localMonthDay(timezone: state.weather.timezone)
            )
            pageStates[key]?.phrase = newPhrase
        }
        // Update stored property for active page
        if let activeState = pageStates[activePageKey] {
            currentPhrase = activeState.phrase
        }
    }

    // MARK: - Formatter cache
    // DateFormatter is expensive to construct. We cache one per (timezone, format)
    // on the main actor (where updateWidget runs), reusing across widget updates.

    private static var hourFormatters: [String: DateFormatter] = [:]
    private static var dayFormatters: [String: DateFormatter] = [:]

    private static func hourFormatter(for tz: TimeZone) -> DateFormatter {
        if let existing = hourFormatters[tz.identifier] { return existing }
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "ha"
        hourFormatters[tz.identifier] = f
        return f
    }

    private static func dayFormatter(for tz: TimeZone) -> DateFormatter {
        if let existing = dayFormatters[tz.identifier] { return existing }
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "EEE"
        dayFormatters[tz.identifier] = f
        return f
    }
}
