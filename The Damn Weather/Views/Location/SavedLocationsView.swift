import SwiftUI
import SwiftData
import CoreLocation
import WeatherKit
import WeatherShared

/// Summary data for a location card
struct LocationSummary: Identifiable, Sendable {
    let id: String
    let temperature: String
    let high: String
    let low: String
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let isDay: Bool
    let phrase: String
}

/// Apple Weather-style locations list with weather cards and sarcastic phrases.
/// Search is inline — tap the search bar to type, results replace cards.
struct SavedLocationsView: View {
    @Query(sort: \SavedLocation.sortOrder) private var locations: [SavedLocation]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let locationService: LocationService
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
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchVM: LocationSearchViewModel?
    @FocusState private var isSearchFocused: Bool

    private let phraseEngine = PhraseEngine()

    private var activeSearchVM: LocationSearchViewModel {
        if let vm = searchVM { return vm }
        let vm = LocationSearchViewModel(locationService: locationService)
        DispatchQueue.main.async { searchVM = vm }
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
                        activeSearchVM.updateSearch(newValue)
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
                    activeSearchVM.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            if isSearching {
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSearching = false
                        isSearchFocused = false
                        searchText = ""
                        activeSearchVM.clear()
                    }
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearching = true
                }
                isSearchFocused = true
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.weatherBgDark
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    if isSearching {
                        searchResultsList
                    } else {
                        ScrollView {
                            cityCardsContent
                        }
                    }
                }
            }
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Intentionally empty — settings moved to main header gear icon
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await fetchAllSummaries()
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            if activeSearchVM.results.isEmpty && !searchText.isEmpty {
                Text("No results found")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(activeSearchVM.results) { result in
                Button {
                    Task {
                        if let selected = await activeSearchVM.selectResult(result) {
                            // Save to SwiftData
                            let saved = SavedLocation(
                                name: selected.name,
                                state: selected.state,
                                country: selected.country,
                                latitude: selected.location.coordinate.latitude,
                                longitude: selected.location.coordinate.longitude
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
                .contextMenu {
                    Button(role: .destructive) {
                        modelContext.delete(location)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Weather Fetching

    private func fetchAllSummaries() async {
        let service = WeatherKit.WeatherService.shared

        // Capture main-actor state before entering task group
        let unit = appState.temperatureUnit
        let phraseMode = appState.phraseMode
        let engine = phraseEngine

        // Extract Sendable data from @Model objects before crossing concurrency boundary
        let locationInfos: [(key: String, location: CLLocation)] = locations.map { loc in
            (key: loc.name + "\(loc.latitude)", location: CLLocation(latitude: loc.latitude, longitude: loc.longitude))
        }

        await withTaskGroup(of: (String, LocationSummary?).self) { group in
            for info in locationInfos {
                let infoKey = info.key
                let infoLocation = info.location
                group.addTask {
                    do {
                        let weather = try await service.weather(
                            for: infoLocation,
                            including: .current, .daily
                        )

                        let current = weather.0
                        let daily = weather.1

                        let windMph = current.wind.speed.converted(to: .milesPerHour).value
                        let conditionTag = WeatherConditionTag.from(current.condition, windSpeed: windMph)
                        let tempF = current.temperature.converted(to: .fahrenheit).value

                        let phrase = await engine.selectPhrase(
                            conditionTag: conditionTag,
                            tempF: tempF,
                            mode: phraseMode,
                            isDay: current.isDaylight
                        )

                        let todayHigh = daily.first.map { $0.highTemperature.converted(to: .fahrenheit).value } ?? 0
                        let todayLow = daily.first.map { $0.lowTemperature.converted(to: .fahrenheit).value } ?? 0

                        let tempStr = unit.format(tempF)
                        let highStr = unit.format(todayHigh)
                        let lowStr = unit.format(todayLow)
                        let condLabel = current.condition.description
                        let isDay = current.isDaylight

                        let summary = LocationSummary(
                            id: infoKey,
                            temperature: tempStr,
                            high: highStr,
                            low: lowStr,
                            conditionTag: conditionTag,
                            conditionLabel: condLabel,
                            isDay: isDay,
                            phrase: phrase
                        )

                        return (infoKey, summary)
                    } catch {
                        return (infoKey, nil)
                    }
                }
            }

            for await (key, summary) in group {
                if let summary {
                    summaries[key] = summary
                }
            }
        }
    }
}
