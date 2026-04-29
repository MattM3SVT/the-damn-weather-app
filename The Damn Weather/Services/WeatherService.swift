import Foundation
import WeatherKit
import CoreLocation
import MapKit
import WeatherShared
import os.log

nonisolated private let weatherLog = Logger(subsystem: "DamnWeather", category: "WeatherService")

actor WeatherService {
    private let service = WeatherKit.WeatherService.shared
    private var cache: [String: WeatherSnapshot] = [:]
    /// Stores the IANA identifier (e.g. "America/Los_Angeles") rather than a
    /// `TimeZone` instance. Reconstructing `TimeZone(identifier:)` on every
    /// read ensures the returned value uses the current DST offset after a
    /// transition (cached `TimeZone` instances capture the offset at creation).
    private var timezoneIdentifierCache: [String: String] = [:]
    private var cachedAttribution: WeatherAttribution?
    private let crossCheck = ObservationCrossCheckService()
    private let airQuality = AirQualityService()
    private let nwsAlerts = NWSAlertsService()

    private func cacheKey(for location: CLLocation) -> String {
        String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
    }

    func fetchWeather(for location: CLLocation) async throws -> WeatherSnapshot {
        let key = cacheKey(for: location)

        // Check cache
        if let cached = cache[key], !cached.isStale {
            return cached
        }

        // Fetch WeatherKit + NWS + METAR + AirNow in parallel. Each supplemental
        // source is non-throwing (cross-check returns empty, air-quality returns
        // nil) so one supplemental failure never cascades into the primary flow.
        async let wkTask = service.weather(
            for: location,
            including: .current, .hourly, .daily, .minute, .alerts
        )
        async let consensusTask = crossCheck.fetchSkyConsensus(for: location)
        async let airQualityTask = airQuality.fetchAirQuality(for: location)
        // NWS alert details for richer in-app rendering. Empty array on
        // non-US locations or any failure — UI falls back to web view.
        async let nwsAlertsTask = nwsAlerts.fetchActiveAlerts(for: location)

        let weather = try await wkTask
        let consensus = await consensusTask
        let airQualityData = await airQualityTask
        let nwsAlertDetails = await nwsAlertsTask

        let current = weather.0
        let hourly = weather.1
        let daily = weather.2
        let minute = weather.3
        let alerts: [WeatherAlert] = weather.4 ?? []

        let windMph = current.wind.speed.converted(to: .milesPerHour).value
        let baseTag = WeatherConditionTag.from(
            current.condition,
            windSpeed: windMph
        )
        let conditionTag = applyConsensusOverride(
            base: baseTag,
            consensus: consensus,
            wkCloudCoverPct: current.cloudCover * 100
        )
        // When override fires, switch the displayed label to the corrected tag's label
        // so the text on screen matches the gradient/icon/phrase. Otherwise preserve
        // WeatherKit's nuanced description (e.g. "Mostly Cloudy" vs "Cloudy").
        let conditionLabel = (conditionTag != baseTag)
            ? conditionTag.label
            : current.condition.description

        // precipitationIntensity — get raw value and convert
        let precipInPerHour = current.precipitationIntensity.value * 0.0393701  // mm to inches approx

        var currentData = CurrentWeatherData(
            temperature: current.temperature.converted(to: .fahrenheit).value,
            feelsLike: current.apparentTemperature.converted(to: .fahrenheit).value,
            humidity: current.humidity * 100,
            isDay: current.isDaylight,
            precipitation: precipInPerHour,
            conditionTag: conditionTag,
            conditionLabel: conditionLabel,
            pressure: current.pressure.converted(to: .hectopascals).value,
            windSpeed: windMph,
            windDirection: current.wind.direction.value,
            windGusts: current.wind.gust?.converted(to: .milesPerHour).value ?? 0,
            cloudCover: current.cloudCover * 100,
            uvIndex: current.uvIndex.value,
            visibility: current.visibility.converted(to: .miles).value,
            dewPoint: current.dewPoint.converted(to: .fahrenheit).value
        )
        #if DEBUG
        currentData.crossCheckDebug = CrossCheckDebugInfo(
            wkDescription: current.condition.description,
            baseTag: baseTag,
            finalTag: conditionTag,
            nws: consensus.nws,
            metar: consensus.metar
        )
        #endif

        // Filter to current hour and forward only — use start-of-current-hour
        // so at 3:43 PM we include 3:00 PM (current hour) but NOT 2:00 PM.
        let now = Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        var hourlyArray = Array(hourly
            .filter { $0.date >= currentHourStart }
            .prefix(24)
            .map { (hour: HourWeather) -> HourlyForecastPoint in
                let hourWindMph = hour.wind.speed.converted(to: .milesPerHour).value
                let hourPrecipInches = hour.precipitationAmount.converted(to: .inches).value
                return HourlyForecastPoint(
                    time: hour.date,
                    temperature: hour.temperature.converted(to: .fahrenheit).value,
                    feelsLike: hour.apparentTemperature.converted(to: .fahrenheit).value,
                    precipitationProbability: hour.precipitationChance * 100,
                    conditionTag: WeatherConditionTag.from(
                        hour.condition,
                        windSpeed: hourWindMph
                    ),
                    windSpeed: hourWindMph,
                    windDirection: hour.wind.direction.value,
                    windGusts: hour.wind.gust?.converted(to: .milesPerHour).value ?? hourWindMph,
                    isDay: hour.isDaylight,
                    humidity: hour.humidity * 100,
                    pressure: hour.pressure.converted(to: .hectopascals).value,
                    visibility: hour.visibility.converted(to: .miles).value,
                    uvIndex: hour.uvIndex.value,
                    dewPoint: hour.dewPoint.converted(to: .fahrenheit).value,
                    cloudCover: hour.cloudCover * 100,
                    precipitationAmount: hourPrecipInches
                )
            })

        // Override the "Now" hour with real-time current observation so the hourly
        // "Now" card matches the hero section exactly (same temp, condition, etc.)
        if let firstHour = hourlyArray.first,
           Calendar.current.isDate(firstHour.time, equalTo: now, toGranularity: .hour) {
            hourlyArray[0] = HourlyForecastPoint(
                time: firstHour.time,
                temperature: currentData.temperature,
                feelsLike: currentData.feelsLike,
                precipitationProbability: firstHour.precipitationProbability,
                conditionTag: currentData.conditionTag,
                windSpeed: currentData.windSpeed,
                windDirection: currentData.windDirection,
                windGusts: currentData.windGusts,
                isDay: currentData.isDay,
                humidity: currentData.humidity,
                pressure: currentData.pressure,
                visibility: currentData.visibility,
                uvIndex: currentData.uvIndex,
                dewPoint: currentData.dewPoint,
                cloudCover: currentData.cloudCover,
                precipitationAmount: firstHour.precipitationAmount
            )
        }

        let dailyData = daily.prefix(10).map { (day: DayWeather) -> DailyForecastPoint in
            let dayWindMph = day.wind.speed.converted(to: .milesPerHour).value
            let precipInches = day.precipitationAmountByType.precipitation.converted(to: .inches).value
            let dayMoonPhase = mapMoonPhase(day.moon.phase)
            let dayMoonIllum = estimateIllumination(for: day.moon.phase)
            return DailyForecastPoint(
                date: day.date,
                high: day.highTemperature.converted(to: .fahrenheit).value,
                low: day.lowTemperature.converted(to: .fahrenheit).value,
                conditionTag: WeatherConditionTag.from(
                    day.condition,
                    windSpeed: dayWindMph
                ),
                conditionLabel: day.condition.description,
                sunrise: day.sun.sunrise ?? day.date,
                sunset: day.sun.sunset ?? day.date,
                precipitationSum: precipInches,
                precipitationProbability: day.precipitationChance * 100,
                windMax: dayWindMph,
                uvIndexMax: day.uvIndex.value,
                moonPhase: dayMoonPhase,
                moonIllumination: dayMoonIllum
            )
        }

        let minuteData: [MinutePrecipitationPoint] = minute?.map { m in
            return MinutePrecipitationPoint(
                time: m.date,
                intensity: m.precipitationIntensity.value * 0.0393701,  // mm to inches
                probability: m.precipitationChance * 100
            )
        } ?? []

        let alertData: [WeatherAlertData] = alerts.map { (alert: WeatherAlert) in
            // Enrich with NWS data when available so the sheet can render the
            // full alert body natively. Match by event name (case-insensitive,
            // trimmed) — WeatherKit uses NWS as its US source so the event
            // strings line up. First match wins on the rare collision.
            let nwsMatch = nwsAlertDetails.first { detail in
                detail.event.caseInsensitiveCompare(alert.summary) == .orderedSame
            }
            return WeatherAlertData(
                headline: alert.summary,
                detailsURL: alert.detailsURL,
                severity: mapSeverity(alert.severity),
                source: alert.source,
                expiresAt: alert.metadata.expirationDate,
                description: nwsMatch?.description,
                instruction: nwsMatch?.instruction,
                areaDesc: nwsMatch?.areaDesc,
                onset: nwsMatch?.onset,
                ends: nwsMatch?.ends
            )
        }

        // Moon phase from today's daily forecast
        let moonPhase: MoonPhaseData? = daily.first.map { day in
            MoonPhaseData(
                phase: mapMoonPhase(day.moon.phase),
                illumination: estimateIllumination(for: day.moon.phase)
            )
        }

        // Get DST-aware timezone via reverse geocoding (cache the IANA identifier,
        // not the TimeZone instance, so DST transitions are reflected on the next read).
        let locationTimezone: TimeZone
        if let cachedID = timezoneIdentifierCache[key],
           let tz = TimeZone(identifier: cachedID) {
            locationTimezone = tz
        } else {
            let tz = await Self.timezone(for: location)
            timezoneIdentifierCache[key] = tz.identifier
            locationTimezone = tz
        }

        let snapshot = WeatherSnapshot(
            current: currentData,
            hourly: hourlyArray,
            daily: dailyData,
            minutePrecipitation: minuteData,
            alerts: alertData,
            moonPhase: moonPhase,
            timezone: locationTimezone,
            fetchedAt: Date(),
            location: location,
            airQuality: airQualityData
        )

        cache[key] = snapshot
        return snapshot
    }

    func fetchAttribution() async -> WeatherAttribution? {
        if let cachedAttribution { return cachedAttribution }
        do {
            let attribution = try await service.attribution
            cachedAttribution = attribution
            return attribution
        } catch {
            return nil
        }
    }

    /// Drop only the WeatherKit in-memory snapshot cache so the next
    /// `fetchWeather` call hits Apple. Supplemental services (cross-check,
    /// air quality, NWS alerts) each have their own TTLs and sticky fallback,
    /// so wiping them on every routine refresh would force re-fetches that
    /// can transiently fail and leave the user with no AQI / suppressed
    /// consensus override / etc. Foreground refresh and pull-to-refresh
    /// route through here.
    func clearCache() async {
        cache.removeAll()
    }

    /// Get the correct timezone for a location via reverse geocoding.
    /// Returns the IANA timezone (e.g. "America/Los_Angeles") which handles DST correctly.
    private static func timezone(for location: CLLocation) async -> TimeZone {
        if #available(iOS 26, *) {
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    return .current
                }
                let items = try await request.mapItems
                if let tz = items.first?.timeZone {
                    return tz
                }
            } catch {
                weatherLog.warning("MK timezone lookup failed: \(error.localizedDescription, privacy: .public) — using device timezone")
            }
        } else {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let tz = placemarks.first?.timeZone {
                    return tz
                }
            } catch {
                weatherLog.warning("CL timezone lookup failed: \(error.localizedDescription, privacy: .public) — using device timezone")
            }
        }
        return .current
    }

    private nonisolated func mapSeverity(_ severity: WeatherSeverity) -> WeatherAlertData.AlertSeverity {
        switch severity {
        case .extreme: return .extreme
        case .severe: return .severe
        case .moderate: return .moderate
        case .minor: return .minor
        default: return .unknown
        }
    }

    private nonisolated func estimateIllumination(for phase: MoonPhase) -> Double {
        switch phase {
        case .new: return 0.0
        case .waxingCrescent: return 0.25
        case .firstQuarter: return 0.5
        case .waxingGibbous: return 0.75
        case .full: return 1.0
        case .waningGibbous: return 0.75
        case .lastQuarter: return 0.5
        case .waningCrescent: return 0.25
        @unknown default: return 0.0
        }
    }

    private nonisolated func mapMoonPhase(_ phase: MoonPhase) -> MoonPhaseData.MoonPhaseType {
        switch phase {
        case .new: return .newMoon
        case .waxingCrescent: return .waxingCrescent
        case .firstQuarter: return .firstQuarter
        case .waxingGibbous: return .waxingGibbous
        case .full: return .fullMoon
        case .waningGibbous: return .waningGibbous
        case .lastQuarter: return .lastQuarter
        case .waningCrescent: return .waningCrescent
        @unknown default: return .newMoon
        }
    }
}
