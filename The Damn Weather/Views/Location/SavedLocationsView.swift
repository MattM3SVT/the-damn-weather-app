import SwiftUI
import SwiftData
import CoreLocation
import WeatherKit
import WeatherShared

/// Apple Weather-style locations list with weather cards and sarcastic phrases.
/// Search is inline — tap the search bar to type, results replace cards.
struct SavedLocationsView: View {
    @Query(sort: \SavedLocation.sortOrder, animation: .smooth) private var locations: [SavedLocation]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let locationService: LocationService
    let phraseEngine: PhraseEngine
    let currentLocationName: String
    let currentTemperature: String
    let currentHigh: String
    let currentLow: String
    let currentConditionTag: WeatherConditionTag
    let currentConditionLabel: String
    let currentIsDay: Bool
    let currentPhrase: String

    let onSelect: (SavedLocation) -> Void
    let onSelectCurrent: () -> Void
    let onAddedLocation: (CLLocation) -> Void

    @State private var summaries: [String: LocationSummary] = [:]
    @State private var deletingIDs: Set<String> = []
    @State private var showDuplicateAlert = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchVM: LocationSearchViewModel?
    @FocusState private var isSearchFocused: Bool

    /// Returns the search VM, creating it if needed.
    /// IMPORTANT: Only call from event handlers (onChange, button actions, .task),
    /// never during body evaluation — creating the VM mutates @State.
    private func ensureSearchVM() -> LocationSearchViewModel {
        if let vm = searchVM { return vm }
        let vm = LocationSearchViewModel(locationService: locationService)
        searchVM = vm
        return vm
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))

            if isSearching {
                TextField("Search for a city or airport", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        ensureSearchVM().updateSearch(newValue)
                    }
            } else {
                Text("Search for a city or airport")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }

            if isSearching && !searchText.isEmpty {
                Button {
                    searchText = ""
                    ensureSearchVM().clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            if isSearching {
                Button("Cancel") {
                    isSearching = false
                    isSearchFocused = false
                    searchText = ""
                    ensureSearchVM().clear()
                }
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal)
        .onTapGesture {
            if !isSearching {
                // Create search VM eagerly here (user action context),
                // so it exists before the body reads it.
                _ = ensureSearchVM()
                isSearching = true
                isSearchFocused = true
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed header: title + search bar
                VStack(alignment: .leading, spacing: 8) {
                    if !isSearching {
                        Text("Weather")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                    }

                    searchBar
                }
                .padding(.top, isSearching ? 4 : 8)
                .padding(.bottom, 8)

                // Content: cards or search results
                if isSearching {
                    searchResultsList
                } else {
                    ScrollView {
                        cityCardsContent
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background(Color.weatherBgDark.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 0.2), value: isSearching)
            .alert("Already Added", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You've already saved that location.")
            }
        }
        .task {
            await fetchAllSummaries()
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            if (searchVM?.results ?? []).isEmpty && !searchText.isEmpty {
                Text("No results found")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(searchVM?.results ?? []) { result in
                Button {
                    Task {
                        if let selected = await ensureSearchVM().selectResult(result) {
                            // Prevent adding the same saved city twice
                            let isDuplicate = locations.contains { existing in
                                abs(existing.latitude - selected.location.coordinate.latitude) < 0.01 &&
                                abs(existing.longitude - selected.location.coordinate.longitude) < 0.01
                            }
                            guard !isDuplicate else {
                                showDuplicateAlert = true
                                return
                            }

                            // Save to SwiftData with incrementing sort order
                            let saved = SavedLocation(
                                name: selected.name,
                                state: selected.state,
                                country: selected.country,
                                latitude: selected.location.coordinate.latitude,
                                longitude: selected.location.coordinate.longitude,
                                sortOrder: locations.count
                            )
                            modelContext.insert(saved)

                            // Dismiss and load
                            dismiss()
                            onAddedLocation(selected.location)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.body)
                            .foregroundStyle(.white)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .transition(.opacity)
    }

    // MARK: - City Cards

    private var cityCardsContent: some View {
        // VStack (not LazyVStack) — enables proper removal animations.
        // Saved city count is small enough that lazy loading isn't needed.
        VStack(spacing: 12) {
            // Current location card
            if !currentLocationName.isEmpty {
                Button {
                    dismiss()
                    onSelectCurrent()
                } label: {
                    LocationWeatherCard(
                        name: currentLocationName.components(separatedBy: ", ").first ?? currentLocationName,
                        state: currentLocationName.components(separatedBy: ", ").dropFirst().first ?? "",
                        temperature: currentTemperature,
                        high: currentHigh,
                        low: currentLow,
                        conditionTag: currentConditionTag,
                        conditionLabel: currentConditionLabel,
                        isDay: currentIsDay,
                        phrase: currentPhrase,
                        isCurrent: true
                    )
                }
                .padding(.horizontal)
            }

            // Saved location cards
            ForEach(locations) { location in
                let locationKey = location.name + "\(location.latitude)"
                let isDeleting = deletingIDs.contains(locationKey)

                Button {
                    dismiss()
                    onSelect(location)
                } label: {
                    if let summary = summaries[location.name + "\(location.latitude)"] {
                        LocationWeatherCard(
                            name: location.name,
                            state: location.state,
                            temperature: summary.temperature,
                            high: summary.high,
                            low: summary.low,
                            conditionTag: summary.conditionTag,
                            conditionLabel: summary.conditionLabel,
                            isDay: summary.isDay,
                            phrase: summary.phrase,
                            isCurrent: false
                        )
                    } else {
                        LocationWeatherCard(
                            name: location.name,
                            state: location.state,
                            temperature: "--°",
                            high: "--°",
                            low: "--°",
                            conditionTag: .partlyCloudy,
                            conditionLabel: "Loading...",
                            isDay: true,
                            phrase: "Hold on, getting the damn weather...",
                            isCurrent: false
                        )
                    }
                }
                .padding(.horizontal)
                .opacity(isDeleting ? 0 : 1)
                .contextMenu {
                    Button(role: .destructive) {
                        deleteLocation(location)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }

    private func deleteLocation(_ location: SavedLocation) {
        let key = location.name + "\(location.latitude)"

        // Phase 1: Fade out the card. The card keeps its space in the VStack
        // so cards below do NOT move yet. The fade runs behind the context
        // menu's dismiss snapshot — by the time the snapshot clears (~0.4s),
        // the card is already invisible.
        _ = withAnimation(.easeIn(duration: 0.7)) {
            deletingIDs.insert(key)
        }

        // Phase 2: After the context menu snapshot is gone AND the fade is
        // complete, delete from SwiftData. This removes the item from ForEach
        // and the VStack smoothly collapses the gap — but the card is already
        // invisible, so the user only sees cards sliding up into empty space.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.smooth(duration: 0.3)) {
                self.modelContext.delete(location)
            }
        }
    }

    // MARK: - Weather Fetching

    private func fetchAllSummaries() async {
        let locationInfos: [(key: String, location: CLLocation)] = locations.map { loc in
            (key: loc.name + "\(loc.latitude)", location: CLLocation(latitude: loc.latitude, longitude: loc.longitude))
        }
        let results = await LocationSummaryFetcher.fetchAll(
            locationInfos: locationInfos,
            unit: appState.temperatureUnit,
            phraseMode: appState.phraseMode,
            phraseEngine: phraseEngine
        )
        summaries.merge(results) { _, new in new }
    }
}
