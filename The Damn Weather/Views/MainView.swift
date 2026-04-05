import SwiftUI
import SwiftData
import CoreLocation
import WeatherShared

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

    private let locationService: LocationService

    init(locationService: LocationService, appState: AppState) {
        self.locationService = locationService
        _weatherVM = State(initialValue: WeatherViewModel(
            locationService: locationService,
            appState: appState
        ))
        _settingsVM = State(initialValue: SettingsViewModel(appState: appState))
    }

    private var isRegular: Bool { sizeClass == .regular }

    /// Total pages: current location (page 0) + saved locations
    private var pageCount: Int { 1 + savedLocations.count }

    var body: some View {
        Group {
            if isRegular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .task {
            // Only auto-fetch if we already have location permission.
            // Otherwise show the "Where the hell are you?" empty state immediately.
            let status = locationService.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                await weatherVM.loadWeatherForCurrentLocation()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await weatherVM.refreshOnForeground()
                }
            }
        }
        .onChange(of: savedLocations.count) { _, _ in
            // Clamp selectedPage when a location is deleted to prevent out-of-bounds
            if selectedPage >= pageCount {
                selectedPage = max(0, pageCount - 1)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - iPad Layout (sidebar + content)

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            if showSidebar {
                LocationSidebar(
                    locationService: locationService,
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
                    onAddedLocation: { location in
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
                                Task { await weatherVM.refreshPhrase() }
                            },
                            showBackground: false
                        )
                    }
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .top)
                    )

                    weatherContent
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

    private var iPhoneLayout: some View {
        ZStack {
            // Layer 1: Background (full screen)
            DynamicBackground(
                condition: weatherVM.weather?.current.conditionTag ?? .clear,
                isDay: weatherVM.weather?.current.isDay ?? true
            )

            // Layer 2: Scrollable content — starts at the very top, scrolls behind header
            TabView(selection: $selectedPage) {
                // Page 0: Current location
                weatherContent
                    .tag(0)

                // Pages 1+: Saved locations
                ForEach(Array(savedLocations.enumerated()), id: \.element.id) { index, _ in
                    weatherContent
                        .tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: selectedPage) { _, newPage in
                heroCollapseProgress = 0
                Task {
                    if newPage == 0 {
                        await weatherVM.loadWeatherForCurrentLocation()
                    } else {
                        let locationIndex = newPage - 1
                        if locationIndex < savedLocations.count {
                            await weatherVM.loadWeather(for: savedLocations[locationIndex])
                        }
                    }
                }
            }

            // Layer 3: Floating header overlay — content scrolls behind this
            VStack(spacing: 0) {
                AppHeaderBar(
                    appState: appState,
                    settingsVM: settingsVM,
                    locationName: weatherVM.displayName,
                    onSearchTap: {},
                    onLogoTap: { showSavedLocations = true },
                    onPhraseModeChanged: {
                        Task { await weatherVM.refreshPhrase() }
                    },
                    showBackground: heroCollapseProgress > 0.3,
                    showSearchBar: false
                )
                .animation(.easeInOut(duration: 0.25), value: heroCollapseProgress > 0.3)

                Spacer()
            }

            // Layer 4: Bottom bar with page dots and list button
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
                    Task { await weatherVM.loadWeatherForCurrentLocation() }
                },
                onAddedLocation: { location in
                    Task { await weatherVM.loadWeather(for: location) }
                    // Navigate to the newly added location (will be last)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedPage = savedLocations.count // count already includes the new one
                    }
                }
            )
        }
    }

    // MARK: - Shared Weather Content

    @ViewBuilder
    private var weatherContent: some View {
        if weatherVM.isLoading && weatherVM.weather == nil {
            ShimmerView()
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
        } else if weatherVM.weather != nil {
            WeatherView(
                viewModel: weatherVM,
                appState: appState,
                sidebarOpen: showSidebar,
                onCollapseProgressChanged: isRegular ? nil : { progress in
                    heroCollapseProgress = progress
                },
                topInset: isRegular ? 0 : headerOverlayHeight
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
