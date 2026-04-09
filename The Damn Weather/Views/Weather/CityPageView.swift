import SwiftUI
import WeatherKit
import WeatherShared

/// A single page in the iPhone city-swiping TabView.
/// Each page renders its own DynamicBackground + weather content independently,
/// so swiping between cities shows pre-loaded data with zero delay.
struct CityPageView: View {
    let pageState: PageWeatherState?
    let isLoading: Bool
    let error: String?
    let appState: AppState
    var sidebarOpen: Bool = false
    var onCollapseProgressChanged: ((CGFloat) -> Void)? = nil
    var topInset: CGFloat = 0
    var onRefreshPhrase: (() -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil
    /// Only page 0 (current location) shows the "Where the hell are you?" empty state.
    /// Saved city pages show a shimmer instead when data isn't loaded yet.
    var isCurrentLocationPage: Bool = false
    var onSearch: (() -> Void)? = nil
    var onUseLocation: (() async -> Void)? = nil
    var attribution: WeatherAttribution? = nil

    var body: some View {
        ZStack {
            // Per-page background — each city gets its own sky gradient
            DynamicBackground(
                condition: pageState?.weather.current.conditionTag ?? .clear,
                isDay: pageState?.weather.current.isDay ?? true
            )

            if let state = pageState {
                WeatherView(
                    weather: state.weather,
                    phrase: state.phrase,
                    locationName: state.displayName,
                    currentTime: state.currentTime,
                    temperatureUnit: appState.temperatureUnit,
                    appState: appState,
                    sidebarOpen: sidebarOpen,
                    onCollapseProgressChanged: onCollapseProgressChanged,
                    onRefreshPhrase: onRefreshPhrase,
                    onRefresh: onRefresh,
                    topInset: topInset,
                    attribution: attribution
                )
            } else if let error {
                ErrorView(message: error) {
                    if let onRefresh {
                        Task { await onRefresh() }
                    }
                }
                .frame(maxHeight: .infinity)
            } else if isCurrentLocationPage && !isLoading {
                // Only page 0 shows the empty state (location permission needed)
                EmptyStateView(
                    onSearch: { onSearch?() },
                    onUseLocation: {
                        if let onUseLocation {
                            Task { await onUseLocation() }
                        }
                    }
                )
                .frame(maxHeight: .infinity)
            } else {
                // Saved city pages or loading current location — show shimmer
                ShimmerView()
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
