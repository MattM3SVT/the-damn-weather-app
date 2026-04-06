import SwiftUI
import SwiftData
import CoreLocation
import WeatherKit
import WeatherShared

/// iPad sidebar — always-visible list of saved locations with weather + phrases.
/// Matches Apple Weather's iPad sidebar pattern.
struct LocationSidebar: View {
    @Query(sort: \SavedLocation.sortOrder) private var locations: [SavedLocation]
    @Environment(\.modelContext) private var modelContext
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
    @Binding var activateSearch: Bool

    @State private var summaries: [String: LocationSummary] = [:]
    @State private var showDuplicateAlert = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchVM: LocationSearchViewModel?
    @FocusState private var isSearchFocused: Bool

    private let phraseEngine = PhraseEngine()

    private func ensureSearchVM() -> LocationSearchViewModel {
        if let vm = searchVM { return vm }
        let vm = LocationSearchViewModel(locationService: locationService)
        searchVM = vm
        return vm
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar spacer
            HStack {
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))

                if isSearching {
                    TextField("Search city or airport", text: $searchText)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newValue in
                            ensureSearchVM().updateSearch(newValue)
                        }
                } else {
                    Text("Search for a city or airport")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }

                if isSearching && !searchText.isEmpty {
                    Button {
                        searchText = ""
                        ensureSearchVM().clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                if isSearching {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearching = false
                            isSearchFocused = false
                            searchText = ""
                            ensureSearchVM().clear()
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onTapGesture {
                if !isSearching {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearching = true
                    }
                    isSearchFocused = true
                }
            }

            if isSearching {
                sidebarSearchResults
            } else {
                sidebarCityCards
            }
        }
        .background(Color.weatherBgDark)
        .alert("Already Added", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've already saved that location.")
        }
        .onChange(of: activateSearch) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = true
                }
                isSearchFocused = true
                activateSearch = false
            }
        }
        .task {
            await fetchAllSummaries()
        }
    }

    // MARK: - Search Results

    private var sidebarSearchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ensureSearchVM().results) { result in
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

                                let saved = SavedLocation(
                                    name: selected.name,
                                    state: selected.state,
                                    country: selected.country,
                                    latitude: selected.location.coordinate.latitude,
                                    longitude: selected.location.coordinate.longitude,
                                    sortOrder: locations.count
                                )
                                modelContext.insert(saved)
                                onAddedLocation(selected.location)

                                withAnimation {
                                    isSearching = false
                                    searchText = ""
                                    ensureSearchVM().clear()
                                }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }

    // MARK: - City Cards

    private var sidebarCityCards: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Current location
                if !currentLocationName.isEmpty {
                    Button { onSelectCurrent() } label: {
                        SidebarLocationCard(
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
                }

                // Saved locations
                ForEach(locations) { location in
                    Button { onSelect(location) } label: {
                        if let summary = summaries[location.name + "\(location.latitude)"] {
                            SidebarLocationCard(
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
                            SidebarLocationCard(
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
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(location)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
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

                        return (infoKey, LocationSummary(
                            id: infoKey,
                            temperature: tempStr,
                            high: highStr,
                            low: lowStr,
                            conditionTag: conditionTag,
                            conditionLabel: condLabel,
                            isDay: isDay,
                            phrase: phrase
                        ))
                    } catch {
                        return (infoKey, nil)
                    }
                }
            }
            var results: [String: LocationSummary] = [:]
            for await (key, summary) in group {
                if let summary {
                    results[key] = summary
                }
            }
            summaries.merge(results) { _, new in new }
        }
    }
}

// MARK: - Sidebar Card (compact version for iPad sidebar)

struct SidebarLocationCard: View {
    let name: String
    let state: String
    let temperature: String
    let high: String
    let low: String
    let conditionTag: WeatherConditionTag
    let conditionLabel: String
    let isDay: Bool
    let phrase: String
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top: name + temp
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    if isCurrent {
                        Text("My Location")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                    if !state.isEmpty {
                        Text(state)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                Text(temperature)
                    .font(.system(size: 32, weight: .thin, design: .rounded))
            }

            // Phrase
            Text(phrase)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)

            // Bottom: condition + high/low
            HStack {
                Text(conditionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("H:\(high)  L:\(low)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background {
            ZStack {
                WeatherGradients.gradient(for: conditionTag, isDay: isDay, colorScheme: .dark)
                LinearGradient(
                    colors: [.white.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .drawingGroup()
    }
}
