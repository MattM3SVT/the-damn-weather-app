import Foundation
import WeatherKit
import CoreLocation
import WeatherShared

actor WeatherService {
    private let service = WeatherKit.WeatherService.shared
    private var cache: [String: WeatherSnapshot] = [:]

    private func cacheKey(for location: CLLocation) -> String {
        String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
    }

    func fetchWeather(for location: CLLocation) async throws -> WeatherSnapshot {
        let key = cacheKey(for: location)

        // Check cache
        if let cached = cache[key], !cached.isStale {
            return cached
        }

        // Fetch all weather data in one call
        let weather = try await service.weather(
            for: location,
            including: .current, .hourly, .daily, .minute, .alerts
        )

        let current = weather.0
        let hourly = weather.1
        let daily = weather.2
        let minute = weather.3
        let alerts: [WeatherAlert] = weather.4 ?? []

        let windMph = current.wind.speed.converted(to: .milesPerHour).value
        let conditionTag = WeatherConditionTag.from(
            current.condition,
            windSpeed: windMph
        )

        // precipitationIntensity — get raw value and convert
        let precipInPerHour = current.precipitationIntensity.value * 0.0393701  // mm to inches approx

        let currentData = CurrentWeatherData(
            temperature: current.temperature.converted(to: .fahrenheit).value,
            feelsLike: current.apparentTemperature.converted(to: .fahrenheit).value,
            humidity: current.humidity * 100,
            isDay: current.isDaylight,
            precipitation: precipInPerHour,
            conditionTag: conditionTag,
            conditionLabel: current.condition.description,
            pressure: current.pressure.converted(to: .hectopascals).value,
            windSpeed: windMph,
            windDirection: current.wind.direction.value,
            windGusts: current.wind.gust?.converted(to: .milesPerHour).value ?? 0,
            cloudCover: current.cloudCover * 100,
            uvIndex: current.uvIndex.value,
            visibility: current.visibility.converted(to: .miles).value,
            dewPoint: current.dewPoint.converted(to: .fahrenheit).value
        )

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
            WeatherAlertData(
                headline: alert.summary,
                description: alert.detailsURL.absoluteString,
                severity: mapSeverity(alert.severity),
                source: alert.source,
                expiresAt: alert.metadata.expirationDate
            )
        }

        // Moon phase from today's daily forecast
        let moonPhase: MoonPhaseData? = daily.first.map { day in
            MoonPhaseData(
                phase: mapMoonPhase(day.moon.phase),
                illumination: estimateIllumination(for: day.moon.phase)
            )
        }

        // Derive timezone from location coordinates (±15° per hour offset)
        let locationTimezone = Self.timezone(for: location) ?? .current

        let snapshot = WeatherSnapshot(
            current: currentData,
            hourly: hourlyArray,
            daily: dailyData,
            minutePrecipitation: minuteData,
            alerts: alertData,
            moonPhase: moonPhase,
            timezone: locationTimezone,
            fetchedAt: Date(),
            location: location
        )

        cache[key] = snapshot
        return snapshot
    }

    func clearCache() {
        cache.removeAll()
    }

    /// Approximate timezone from longitude. Each 15° of longitude ≈ 1 hour offset.
    /// This is sufficient for weather display (sunrise/sunset, hourly labels).
    private nonisolated static func timezone(for location: CLLocation) -> TimeZone? {
        let offsetSeconds = Int((location.coordinate.longitude / 15).rounded()) * 3600
        return TimeZone(secondsFromGMT: offsetSeconds)
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
