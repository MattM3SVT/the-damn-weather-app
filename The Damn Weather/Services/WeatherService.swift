import Foundation
import WeatherKit
import CoreLocation
import WeatherShared

actor WeatherService {
    private let service = WeatherKit.WeatherService.shared
    private var cache: [String: WeatherSnapshot] = [:]

    private func cacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
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

        let hourlyData = hourly.prefix(24).map { (hour: HourWeather) -> HourlyForecastPoint in
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
        }

        let dailyData = daily.prefix(10).map { (day: DayWeather) -> DailyForecastPoint in
            let dayWindMph = day.wind.speed.converted(to: .milesPerHour).value
            let precipInches = day.precipitationAmountByType.precipitation.converted(to: .inches).value
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
                uvIndexMax: day.uvIndex.value
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
                illumination: day.moon.phase == .full ? 1.0
                    : day.moon.phase == .new ? 0.0
                    : 0.5
            )
        }

        let snapshot = WeatherSnapshot(
            current: currentData,
            hourly: hourlyData,
            daily: dailyData,
            minutePrecipitation: minuteData,
            alerts: alertData,
            moonPhase: moonPhase,
            timezone: .current,
            fetchedAt: Date(),
            location: location
        )

        cache[key] = snapshot
        return snapshot
    }

    func clearCache() {
        cache.removeAll()
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
