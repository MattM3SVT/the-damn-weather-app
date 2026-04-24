import SwiftUI
import SwiftData
import CoreLocation
import WeatherShared
import WidgetKit
import os.log

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SavedLocation.sortOrder) private var savedLocations: [SavedLocation]

    @State private var weatherVM: WeatherViewModel
    @State private var settingsVM: SettingsViewModel
    @State private var showSavedLocations = false
    @State private var showSidebar = false
    @State private var sidebarSearchActive = false
    @State private var selectedPage = 0
    @State private var heroCollapseProgress: CGFloat = 0
    /// Tracks the active saved city by identity so reorder/delete inside the modal
    /// can restore the correct page on dismiss (index-based selectedPage alone is unsafe).
    @State private var activeSavedLocationID: SavedLocation.ID?

    private let locationService: LocationService

    init(locationService: LocationService, appState: AppState) {
        self.locationService = locationService
        _weatherVM = State(initialValue: WeatherViewModel(
            locationService: locationService,
            appState: appState
        ))
        _settingsVM = State(initialValue: SettingsViewModel(appState: appState))
    }

    /// Minimum width to use the iPad sidebar layout. iPad Mini portrait is
    /// 744pt — too narrow for a 320pt sidebar plus a usable weather pane —
    /// so it falls back to the iPhone TabView layout. Matches Apple Weather's
    /// behavior: sidebar appears only on regular-width iPads.
    private let iPadLayoutWidthThreshold: CGFloat = 768

    private func shouldUseIPadLayout(width: CGFloat) -> Bool {
        sizeClass == .regular && width >= iPadLayoutWidthThreshold
    }

    /// Total pages: current location (page 0) + saved locations
    private var pageCount: Int { 1 + savedLocations.count }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if shouldUseIPadLayout(width: geometry.size.width) {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            }
        }
        .task {
            // Diagnostic: check widget data store state on launch
            #if DEBUG
            Logger(subsystem: "DamnWeather", category: "Launch").info("Widget DataStore Diagnostic:\n\(WidgetDataStore.diagnose(), privacy: .public)")
            #endif
            // Seed the widget cache on first install so a widget added before
            // the app has fetched weather renders something contextual.
            WidgetDataStore.saveSeedIfMissing()
            // Backfill UUIDs on SavedLocations inserted before the uuid field existed,
            // then mirror the full list to the App Group container so the widget's
            // Edit-Widget picker reflects the user's current cities.
            backfillSavedLocationUUIDs()
            SavedLocationsStore.save(widgetLocationEntities())
            syncSavedLocationUUIDMap()
            // Hydrate pageStates from the widget's persistent App Group cache
            // synchronously so the skeleton is replaced with real (if stale)
            // data before we kick off the network fetch. The fresh fetch below
            // overwrites these partials as soon as it returns.
            let status = locationService.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                weatherVM.hydrateFromWidgetCache(savedLocations: savedLocations)
                await weatherVM.loadWeatherForCurrentLocation()
                // Pre-fetch all saved cities in background for instant swiping
                await weatherVM.prefetchAllLocations(savedLocations)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await weatherVM.refreshOnForeground()
                    // Re-prefetch all saved cities after foreground refresh
                    await weatherVM.prefetchAllLocations(savedLocations)
                }
            }
        }
        .onChange(of: savedLocations.count) { oldCount, newCount in
            // Clamp selectedPage when a location is deleted to prevent out-of-bounds
            if selectedPage >= pageCount {
                selectedPage = max(0, pageCount - 1)
            }
            // Prefetch weather for newly-added cities so swiping to them is instant.
            // Skips on delete (newCount < oldCount) to avoid redundant work.
            if newCount > oldCount {
                Task { await weatherVM.prefetchAllLocations(savedLocations) }
            }
        }
        // Mirror the saved-cities list to the App Group whenever the user
        // adds, deletes, or reorders cities. Uses a composite signature
        // because SwiftData's @Model array doesn't conform to Equatable and
        // `.count` wouldn't catch reorder-only changes.
        .onChange(of: savedLocationsSignature) { _, _ in
            SavedLocationsStore.save(widgetLocationEntities())
            syncSavedLocationUUIDMap()
            // Nudge WidgetKit so any widget configured for a just-deleted city
            // refreshes and falls back to My Location immediately.
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: showSavedLocations) { wasShown, isShown in
            // On modal dismiss, restore the user's active city by identity —
            // savedLocations indices may have shifted due to reorder inside the modal.
            guard wasShown, !isShown else { return }
            DispatchQueue.main.async {
                // Page 0 (current location): nothing to restore.
                guard selectedPage > 0 else { return }
                // Already correct — user didn't reorder/delete the active city.
                if selectedPage - 1 < savedLocations.count,
                   let activeID = activeSavedLocationID,
                   savedLocations[selectedPage - 1].id == activeID {
                    return
                }
                // Active city still exists at a new index — restore.
                if let activeID = activeSavedLocationID,
                   let newIndex = savedLocations.firstIndex(where: { $0.id == activeID }) {
                    selectedPage = newIndex + 1
                    return
                }
                // Active city was deleted — fall back to current location (Apple Weather UX).
                selectedPage = 0
                activeSavedLocationID = nil
            }
        }
        .preferredColorScheme(.dark)
        // Clamp Dynamic Type so accessibility-sized users get some scaling (semantic
        // fonts honor this) without the hero 96pt and chrome layouts blowing up at
        // .accessibility3+ sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: - iPad Layout (sidebar + content)

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            if showSidebar {
                LocationSidebar(
                    locationService: locationService,
                    phraseEngine: weatherVM.phraseEngine,
                    currentLocationName: weatherVM.currentLocationDisplayName,
                    currentTemperature: weatherVM.currentLocationWeather.map { appState.temperatureUnit.format($0.current.temperature) } ?? "--°",
                    currentHigh: weatherVM.currentLocationWeather?.daily.first.map { appState.temperatureUnit.format($0.high) } ?? "--°",
                    currentLow: weatherVM.currentLocationWeather?.daily.first.map { appState.temperatureUnit.format($0.low) } ?? "--°",
                    currentConditionTag: weatherVM.currentLocationWeather?.current.conditionTag ?? .clear,
                    currentConditionLabel: weatherVM.currentLocationWeather?.current.conditionLabel ?? "",
                    currentIsDay: weatherVM.currentLocationWeather?.current.isDay ?? true,
                    currentPhrase: weatherVM.currentLocationPhrase,
                    onSelect: { location in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSidebar = false
                        }
                        Task { await weatherVM.loadWeather(for: location) }
                    },
                    onSelectCurrent: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSidebar = false
                        }
                        weatherVM.showCurrentLocation()
                    },
                    onAddedLocation: { location, _ in
                        Task { await weatherVM.loadWeather(for: location) }
                    },
                    activateSearch: $sidebarSearchActive
                )
                .frame(width: 320)
                .transition(.move(edge: .leading))
            }

            ZStack {
                DynamicBackground(
                    condition: weatherVM.weather?.current.conditionTag ?? .clear,
                    isDay: weatherVM.weather?.current.isDay ?? true
                )

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSidebar.toggle()
                            }
                        } label: {
                            Image(systemName: "sidebar.leading")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 44, height: 44)
                        }
                        .padding(.leading, 8)

                        AppHeaderBar(
                            appState: appState,
                            settingsVM: settingsVM,
                            locationName: weatherVM.displayName,
                            onSearchTap: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showSidebar = true
                                }
                                sidebarSearchActive = true
                            },
                            onLogoTap: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showSidebar.toggle()
                                }
                            },
                            onPhraseModeChanged: {
                                Task {
                                    await weatherVM.refreshPhrase()
                                    await weatherVM.updateWidget(for: weatherVM.activePageKey)
                                }
                            },
                            showBackground: false,
                            shareWeather: weatherVM.weather?.current,
                            sharePhrase: weatherVM.currentPhrase,
                            shareLocationName: weatherVM.displayName,
                            shareTimezone: weatherVM.weather?.timezone ?? .current,
                            shareAttribution: weatherVM.weatherAttribution
                        )
                    }
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .top)
                    )

                    iPadWeatherContent
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if showSidebar {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar = false
                    }
                }
            }
        }
    }

    // MARK: - iPhone Layout (paging between cities)

    /// Height of the floating header overlay so scroll content starts below it.
    private let headerOverlayHeight: CGFloat = 48

    /// The display name for the currently active page (drives the header bar).
    private var activeDisplayName: String {
        if let state = weatherVM.pageStates[weatherVM.activePageKey] {
            return state.displayName
        }
        return weatherVM.displayName
    }

    private var iPhoneLayout: some View {
        ZStack {
            // Root background — covers the status bar area that per-page backgrounds
            // inside the TabView can't reach (TabView only ignores bottom safe area).
            DynamicBackground(
                condition: weatherVM.pageStates[weatherVM.activePageKey]?.weather.current.conditionTag ?? .clear,
                isDay: weatherVM.pageStates[weatherVM.activePageKey]?.weather.current.isDay ?? true
            )

            // TabView with per-page CityPageView — each page has its own background + data
            TabView(selection: $selectedPage) {
                // Page 0: Current location
                CityPageView(
                    pageState: weatherVM.pageStates[WeatherViewModel.currentLocationKey],
                    isLoading: weatherVM.isLoading,
                    error: weatherVM.error,
                    appState: appState,
                    onCollapseProgressChanged: { heroCollapseProgress = $0 },
                    topInset: headerOverlayHeight,
                    onRefreshPhrase: { Task { await weatherVM.refreshPhraseForPage(WeatherViewModel.currentLocationKey) } },
                    onRefresh: { await weatherVM.refresh() },
                    isCurrentLocationPage: true,
                    onSearch: { showSavedLocations = true },
                    onUseLocation: { await weatherVM.loadWeatherForCurrentLocation() },
                    attribution: weatherVM.weatherAttribution
                )
                .tag(0)

                // Pages 1+: Saved locations — each gets its own pre-loaded data
                ForEach(Array(savedLocations.enumerated()), id: \.element.id) { index, location in
                    CityPageView(
                        pageState: weatherVM.pageStates[weatherVM.pageKey(for: location)],
                        isLoading: false,
                        error: nil,
                        appState: appState,
                        onCollapseProgressChanged: { heroCollapseProgress = $0 },
                        topInset: headerOverlayHeight,
                        onRefreshPhrase: { Task { await weatherVM.refreshPhraseForPage(weatherVM.pageKey(for: location)) } },
                        onRefresh: { await weatherVM.refreshPage(for: location) },
                        attribution: weatherVM.weatherAttribution
                    )
                    .tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            // Sync active page state into the view model. Widgets no longer
            // follow the app's active page — each widget has its own
            // AppIntent-configured location — so this only updates in-app
            // display state. Widget refreshes happen via prefetchAllLocations
            // on launch/foreground and the widget's own 15-minute timeline.
            .onChange(of: selectedPage) { _, newPage in
                heroCollapseProgress = 0
                if newPage == 0 {
                    weatherVM.activePageKey = WeatherViewModel.currentLocationKey
                    weatherVM.showCurrentLocation()
                    activeSavedLocationID = nil
                } else if newPage - 1 < savedLocations.count {
                    let location = savedLocations[newPage - 1]
                    let key = weatherVM.pageKey(for: location)
                    weatherVM.activePageKey = key
                    if let state = weatherVM.pageStates[key] {
                        weatherVM.weather = state.weather
                        weatherVM.locationName = state.locationName
                        weatherVM.locationState = state.locationState
                        weatherVM.currentPhrase = state.phrase
                    }
                    activeSavedLocationID = location.id
                }
            }

            // Floating header overlay — content scrolls behind this
            VStack(spacing: 0) {
                AppHeaderBar(
                    appState: appState,
                    settingsVM: settingsVM,
                    locationName: activeDisplayName,
                    onSearchTap: {},
                    onLogoTap: { showSavedLocations = true },
                    onPhraseModeChanged: {
                        Task {
                            await weatherVM.refreshAllPagePhrases()
                            await weatherVM.updateWidget(for: weatherVM.activePageKey)
                        }
                    },
                    showBackground: heroCollapseProgress > 0.3,
                    showSearchBar: false,
                    shareWeather: weatherVM.pageStates[weatherVM.activePageKey]?.weather.current,
                    sharePhrase: weatherVM.pageStates[weatherVM.activePageKey]?.phrase ?? "",
                    shareLocationName: activeDisplayName,
                    shareTimezone: weatherVM.pageStates[weatherVM.activePageKey]?.weather.timezone ?? .current,
                    shareAttribution: weatherVM.weatherAttribution
                )
                .animation(.easeInOut(duration: 0.25), value: heroCollapseProgress > 0.3)

                Spacer()
            }

            // Bottom bar with page dots and list button
            VStack {
                Spacer()
                FloatingBottomBar(
                    currentPage: selectedPage,
                    pageCount: pageCount,
                    onListTap: { showSavedLocations = true }
                )
            }
        }
        .fullScreenCover(isPresented: $showSavedLocations) {
            SavedLocationsView(
                locationService: locationService,
                phraseEngine: weatherVM.phraseEngine,
                currentLocationName: weatherVM.currentLocationDisplayName,
                currentTemperature: weatherVM.currentLocationWeather.map { appState.temperatureUnit.format($0.current.temperature) } ?? "--°",
                currentHigh: weatherVM.currentLocationWeather?.daily.first.map { appState.temperatureUnit.format($0.high) } ?? "--°",
                currentLow: weatherVM.currentLocationWeather?.daily.first.map { appState.temperatureUnit.format($0.low) } ?? "--°",
                currentConditionTag: weatherVM.currentLocationWeather?.current.conditionTag ?? .clear,
                currentConditionLabel: weatherVM.currentLocationWeather?.current.conditionLabel ?? "",
                currentIsDay: weatherVM.currentLocationWeather?.current.isDay ?? true,
                currentPhrase: weatherVM.currentLocationPhrase,
                onSelect: { location in
                    // Find the index of the selected location and navigate to it
                    if let index = savedLocations.firstIndex(where: { $0.id == location.id }) {
                        selectedPage = index + 1
                    }
                    Task { await weatherVM.loadWeather(for: location) }
                },
                onSelectCurrent: {
                    selectedPage = 0
                    weatherVM.showCurrentLocation()
                },
                onAddedLocation: { location, newID in
                    Task { await weatherVM.loadWeather(for: location) }
                    // Resolve the new city's index by identity after @Query propagates
                    // the insert. The 0.3s delay also covers the modal dismiss animation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let index = savedLocations.firstIndex(where: { $0.id == newID }) {
                            activeSavedLocationID = newID
                            selectedPage = index + 1
                        }
                    }
                }
            )
        }
    }

    // MARK: - Widget location mirror

    /// Stable signature of the saved-cities list that changes whenever any
    /// city is added, removed, renamed, or reordered. Used by `onChange` to
    /// trigger a mirror write; composite because SavedLocation isn't Equatable.
    private var savedLocationsSignature: String {
        savedLocations.map { "\($0.uuid):\($0.sortOrder):\($0.name)" }.joined(separator: "|")
    }

    /// Build the `LocationEntity` list the widget's Edit-Widget picker shows.
    /// Order matches the user's in-app sort. "My Location" is prepended by the
    /// widget's EntityQuery itself — we only export the saved cities here.
    private func widgetLocationEntities() -> [LocationEntity] {
        savedLocations.map { loc in
            LocationEntity(
                id: loc.uuid,
                name: loc.displayName,
                latitude: loc.latitude,
                longitude: loc.longitude
            )
        }
    }

    /// Hand the view model a fresh pageKey → uuid map so `updateWidget` can
    /// route per-location data into the right multi-cache entry.
    private func syncSavedLocationUUIDMap() {
        weatherVM.savedLocationUUIDs = Dictionary(
            uniqueKeysWithValues: savedLocations.map { (weatherVM.pageKey(for: $0), $0.uuid) }
        )
    }

    /// One-time migration: assign a UUID to any SavedLocation still carrying
    /// the default empty string from before the `uuid` field existed.
    private func backfillSavedLocationUUIDs() {
        var didMutate = false
        for loc in savedLocations where loc.uuid.isEmpty {
            loc.uuid = UUID().uuidString
            didMutate = true
        }
        if didMutate {
            try? modelContext.save()
        }
    }

    // MARK: - iPad Weather Content

    @ViewBuilder
    private var iPadWeatherContent: some View {
        if weatherVM.isLoading && weatherVM.weather == nil {
            ShimmerView()
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
        } else if let weather = weatherVM.weather {
            WeatherView(
                weather: weather,
                phrase: weatherVM.currentPhrase,
                locationName: weatherVM.displayName,
                currentTime: weatherVM.currentTime,
                temperatureUnit: weatherVM.temperatureUnit,
                appState: appState,
                sidebarOpen: showSidebar,
                onRefreshPhrase: {
                    Task {
                        await weatherVM.refreshPhrase()
                        await weatherVM.updateWidget(for: weatherVM.activePageKey)
                    }
                },
                onRefresh: {
                    await weatherVM.refresh()
                },
                attribution: weatherVM.weatherAttribution
            )
        } else if let error = weatherVM.error,
                  locationService.authorizationStatus != .denied,
                  locationService.authorizationStatus != .restricted,
                  locationService.authorizationStatus != .notDetermined {
            // Only show error view for non-permission errors (e.g. network failure)
            ErrorView(message: error) {
                Task { await weatherVM.loadWeatherForCurrentLocation() }
            }
            .frame(maxHeight: .infinity)
        } else {
            // Show empty state for fresh launch, permission denied, or permission not yet granted
            EmptyStateView {
                showSavedLocations = true
            } onUseLocation: {
                Task { await weatherVM.loadWeatherForCurrentLocation() }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let onSearch: () -> Void
    let onUseLocation: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.spaceLG) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Where the hell are you?")
                .font(.title2.bold())

            Text("Enter a city or let us find you so we can tell you what the damn weather is.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.spaceLG)

            VStack(spacing: 12) {
                Button(action: onUseLocation) {
                    Label("Use My Location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentRed)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                }

                Button(action: onSearch) {
                    Label("Search Location", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                }
            }
            .padding(.horizontal, DesignTokens.spaceLG)
        }
        .frame(maxWidth: 500)
    }
}

// MARK: - Error State

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.spaceLG) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("Well, damn.")
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.spaceLG)

            Button(action: onRetry) {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentRed)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            }
            .padding(.horizontal, DesignTokens.spaceLG)
        }
        .frame(maxWidth: 500)
    }
}
