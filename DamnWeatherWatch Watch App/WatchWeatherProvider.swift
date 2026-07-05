import CoreLocation
import Foundation
import WeatherKit
import WeatherShared
import os.log

nonisolated private let watchLog = Logger(subsystem: "DamnWeather", category: "WatchProvider")

/// Fetch pipeline for the watch: one location fix, one WeatherKit call, one
/// phrase. No supplemental sources (NWS/METAR/AirNow) — the watch surface
/// doesn't show them and the battery budget is tight.
@Observable
final class WatchWeatherProvider: NSObject, CLLocationManagerDelegate {
    struct HourPoint: Identifiable {
        let id = UUID()
        let hour: String
        let temp: Int
        let tag: WeatherConditionTag
        let isDay: Bool
    }

    struct DayPoint: Identifiable {
        let id = UUID()
        let day: String
        let high: Int
        let low: Int
        let tag: WeatherConditionTag
    }

    struct State {
        var temperature: Int
        var conditionTag: WeatherConditionTag
        var conditionLabel: String
        var isDay: Bool
        var phrase: String
        var high: Int
        var low: Int
        var feelsLike: Int
        var windMph: Int
        var humidity: Int
        var uvIndex: Int
        var locationName: String
        var hourly: [HourPoint]
        var daily: [DayPoint]
        var fetchedAt: Date
    }

    var state: State?
    var errorMessage: String?
    private(set) var isLoading = false

    var isStale: Bool {
        guard let state else { return true }
        return Date().timeIntervalSince(state.fetchedAt) > AppConstants.weatherCacheTTL
    }

    private let manager = CLLocationManager()
    private let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Refresh only when the data has aged past the cache TTL (or never
    /// loaded). Called from onAppear/scenePhase so wrist-raises are free.
    func refreshIfStale() async {
        guard isStale else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        guard let location = await requestLocation() else {
            watchLog.error("location unavailable (auth=\(self.manager.authorizationStatus.rawValue))")
            errorMessage = "No damn location. Check permissions on your phone."
            return
        }
        watchLog.info("fetching weather for \(location.coordinate.latitude), \(location.coordinate.longitude)")

        do {
            let weather = try await WeatherService.shared.weather(
                for: location, including: .current, .hourly, .daily
            )
            let current = weather.0
            let windMph = current.wind.speed.converted(to: .milesPerHour).value
            let tag = WeatherConditionTag.from(current.condition, windSpeed: windMph)
            let tempF = current.temperature.converted(to: .fahrenheit).value

            // Clean phrases only on the watch: glanceable surface, and the
            // watch has no explicit-mode setting of its own.
            let phrase = await phraseEngine.selectPhrase(
                conditionTag: tag,
                tempF: tempF,
                mode: .clean,
                isDay: current.isDaylight,
                localHour: Date().localHour(),
                localMonthDay: Date().localMonthDay(),
                localIsWeekend: Date().isWeekend(),
                maxLength: 70,
                trackAsSeen: false
            )

            let hourStart = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
            let hourly = weather.1
                .filter { $0.date >= hourStart }
                .prefix(6)
                .enumerated()
                .map { index, h in
                    HourPoint(
                        hour: index == 0 ? "Now" : h.date.hourLabel().replacingOccurrences(of: " ", with: ""),
                        temp: Int(h.temperature.converted(to: .fahrenheit).value.rounded()),
                        tag: WeatherConditionTag.from(h.condition),
                        isDay: h.isDaylight
                    )
                }

            let daily = weather.2.prefix(5).enumerated().map { index, d in
                DayPoint(
                    day: d.date.dayLabel(index: index),
                    high: Int(d.highTemperature.converted(to: .fahrenheit).value.rounded()),
                    low: Int(d.lowTemperature.converted(to: .fahrenheit).value.rounded()),
                    tag: WeatherConditionTag.from(d.condition)
                )
            }

            state = State(
                temperature: Int(tempF.rounded()),
                conditionTag: tag,
                conditionLabel: current.condition.description,
                isDay: current.isDaylight,
                phrase: phrase,
                high: weather.2.first.map { Int($0.highTemperature.converted(to: .fahrenheit).value.rounded()) } ?? 0,
                low: weather.2.first.map { Int($0.lowTemperature.converted(to: .fahrenheit).value.rounded()) } ?? 0,
                feelsLike: Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
                windMph: Int(windMph.rounded()),
                humidity: Int((current.humidity * 100).rounded()),
                uvIndex: current.uvIndex.value,
                locationName: await cityName(for: location) ?? "My Location",
                hourly: Array(hourly),
                daily: Array(daily),
                fetchedAt: Date()
            )
        } catch {
            watchLog.error("WeatherKit fetch failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't fetch the damn weather. Try again."
        }
    }

    /// Swap just the phrase (tap gesture), no network involved.
    func newPhrase() async {
        guard let current = state else { return }
        let phrase = await phraseEngine.selectPhrase(
            conditionTag: current.conditionTag,
            tempF: Double(current.temperature),
            mode: .clean,
            isDay: current.isDay,
            localHour: Date().localHour(),
            localMonthDay: Date().localMonthDay(),
            localIsWeekend: Date().isWeekend(),
            maxLength: 70
        )
        state?.phrase = phrase
    }

    // MARK: - Location

    private func requestLocation() async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < 10 * 60 {
            return cached
        }
        return await withCheckedContinuation { cont in
            continuation?.resume(returning: nil)
            continuation = cont
            manager.requestLocation()
        }
    }

    private func cityName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.locality
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
