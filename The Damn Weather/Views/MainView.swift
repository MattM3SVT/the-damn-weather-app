import SwiftUI
import SwiftData
import CoreLocation
import WeatherShared

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \SavedLocation.sortOrder) private var savedLocations: [SavedLocation]

    @State private var weatherVM: WeatherViewModel
    @State private var settingsVM: SettingsViewModel
    @State private var showSavedLocations = false
    @State private var showSidebar = false
    @State private var sidebarSearchActive = false
    @State private var selectedPage = 0

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
        .preferredColorScheme(.dark)
    }

    // MARK: - iPad Layout (sidebar + content)

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            if showSidebar {
                LocationSidebar(
                    locationService: locationService,
                    currentLocationName: weatherVM.displayName,
                    currentTemperature: weatherVM.weather.map { appState.temperatureUnit.format($0.current.temperature) } ?? "--°",
                    currentHigh: weatherVM.weather?.daily.first.map { appState.temperatureUnit.format($0.high) } ?? "--°",
                    currentLow: weatherVM.weather?.daily.first.map { appState.temperatureUnit.format($0.low) } ?? "--°",
                    currentConditionTag: weatherVM.weather?.current.conditionTag ?? .clear,
                    currentConditionLabel: weatherVM.weather?.current.conditionLabel ?? "",
                    currentIsDay: weatherVM.weather?.current.isDay ?? true,
                    currentPhrase: weatherVM.currentPhrase,
                    onSelect: { location in
                        Task { await weatherVM.loadWeather(for: location) }
                    },
                    onSelectCurrent: {
                        Task { await weatherVM.loadWeatherForCurrentLocation() }
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

    private var iPhoneLayout: some View {
        ZStack {
            // Background matches whichever page is active
            DynamicBackground(
                condition: weatherVM.weather?.current.conditionTag ?? .clear,
                isDay: weatherVM.weather?.current.isDay ?? true
            )

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
                    showSearchBar: false
                )

                // Paging TabView
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
                .onChange(of: selectedPage) { _, newPage in
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
            }

            // Floating bottom bar with page dots
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
                currentLocationName: weatherVM.displayName,
                currentTemperature: weatherVM.weather.map { appState.temperatureUnit.format($0.current.temperature) } ?? "--°",
                currentHigh: weatherVM.weather?.daily.first.map { appState.temperatureUnit.format($0.high) } ?? "--°",
                currentLow: weatherVM.weather?.daily.first.map { appState.temperatureUnit.format($0.low) } ?? "--°",
                currentConditionTag: weatherVM.weather?.current.conditionTag ?? .clear,
                currentConditionLabel: weatherVM.weather?.current.conditionLabel ?? "",
                currentIsDay: weatherVM.weather?.current.isDay ?? true,
                currentPhrase: weatherVM.currentPhrase,
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
            WeatherView(viewModel: weatherVM, appState: appState)
        } else if weatherVM.error != nil,
                  locationService.authorizationStatus != .denied,
                  locationService.authorizationStatus != .restricted,
                  locationService.authorizationStatus != .notDetermined {
            // Only show error view for non-permission errors (e.g. network failure)
            ErrorView(message: weatherVM.error!) {
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
                .padding(.horizontal, 40)

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
            .padding(.horizontal, 40)
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
                .padding(.horizontal, 40)

            Button(action: onRetry) {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentRed)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: 500)
    }
}
