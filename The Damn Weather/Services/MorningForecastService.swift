import Foundation
import BackgroundTasks
import CoreLocation
import UserNotifications
import WeatherShared
import os.log

nonisolated private let morningLog = Logger(subsystem: "DamnWeather", category: "MorningForecast")

/// Schedules the "Good morning, here's the damn weather" notification with
/// real forecast numbers instead of a canned string.
///
/// Freshness model (no push backend):
///  1. Whenever the app has a fresh device-location snapshot (launch,
///     foreground, silent refresh), `scheduleFromSnapshot` rewrites the
///     pending notification with that data.
///  2. A `BGAppRefreshTask` asks iOS to wake the app shortly before delivery
///     to re-fetch. iOS treats the request as advisory — if it never runs,
///     the notification still fires with the most recent data from (1),
///     which is at worst "since you last used the app".
///
/// The notification body describes the *delivery-hour* forecast (pulled from
/// the hourly array), not "right now at scheduling time", so content written
/// at 10 PM still reads correctly at 7 AM.
final class MorningForecastService {
    static let shared = MorningForecastService()
    static let backgroundTaskID = "com.damnweather.morning-forecast-refresh"
    private static let notificationID = "morning-forecast"

    private let weatherService = WeatherService()
    private let phraseEngine = PhraseEngine(
        defaults: UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    )

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.morningForecastEnabled)
    }

    private var deliveryHour: Int {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.morningForecastTime) as? Int ?? 7
    }

    // MARK: - Registration (must run before the app finishes launching)

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                let success = await MorningForecastService.shared.backgroundRefresh()
                refreshTask.setTaskCompleted(success: success)
            }
            refreshTask.expirationHandler = {
                work.cancel()
            }
        }
    }

    // MARK: - Settings entry points

    /// Called when the user toggles the feature or changes the time.
    func updateSchedule() async {
        guard isEnabled else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskID)
            return
        }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            morningLog.info("notification permission denied; morning forecast stays unscheduled")
            return
        }
        _ = await backgroundRefresh()
    }

    // MARK: - Content refresh paths

    /// Cheap path: the app just fetched a device-location snapshot anyway —
    /// reuse it for the notification content. No-op when disabled.
    func scheduleFromSnapshot(_ snapshot: WeatherSnapshot) async {
        guard isEnabled, !snapshot.isPartial else { return }
        await scheduleNotification(from: snapshot)
        scheduleNextBackgroundRefresh()
    }

    /// BG-task path: fetch fresh weather for the last-known device location.
    /// Returns false when disabled, no stored coordinate, or the fetch fails
    /// (the previously scheduled notification is left in place).
    func backgroundRefresh() async -> Bool {
        guard isEnabled else { return false }
        // Always re-arm the next wake-up first — a transient failure below
        // shouldn't silence tomorrow's refresh.
        scheduleNextBackgroundRefresh()

        let group = UserDefaults(suiteName: AppConstants.appGroupID)
        guard let lat = group?.object(forKey: AppConstants.UserDefaultsKeys.lastKnownLatitude) as? Double,
              let lon = group?.object(forKey: AppConstants.UserDefaultsKeys.lastKnownLongitude) as? Double else {
            morningLog.info("no last-known coordinate; keeping previously scheduled content")
            return false
        }
        do {
            let snapshot = try await weatherService.fetchWeather(
                for: CLLocation(latitude: lat, longitude: lon)
            )
            await scheduleNotification(from: snapshot)
            return true
        } catch {
            morningLog.error("background fetch failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - Private

    /// Next occurrence of the configured delivery time in the location's
    /// timezone-agnostic device clock (the user picks "7 AM" meaning their
    /// device's 7 AM).
    private func nextDeliveryDate() -> Date {
        var components = DateComponents()
        components.hour = deliveryHour
        components.minute = 0
        return Calendar.current.nextDate(
            after: Date(), matching: components, matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(24 * 3600)
    }

    private func scheduleNotification(from snapshot: WeatherSnapshot) async {
        let delivery = nextDeliveryDate()
        let calendar = Calendar.current

        // Forecast at the delivery hour; fall back to current conditions when
        // the hourly array doesn't reach that far.
        let hourPoint = snapshot.hourly.first {
            calendar.isDate($0.time, equalTo: delivery, toGranularity: .hour)
        }
        let temp = Int((hourPoint?.temperature ?? snapshot.current.temperature).rounded())
        let tag = hourPoint?.conditionTag ?? snapshot.current.conditionTag

        // High/low for the delivery day, not the scheduling day.
        let day = snapshot.daily.first {
            calendar.isDate($0.date, equalTo: delivery, toGranularity: .day)
        } ?? snapshot.daily.first
        let highLow = day.map { "High \(Int($0.high.rounded()))°, low \(Int($0.low.rounded()))°. " } ?? ""

        // Context lines, in priority order. Each is a short sentence; all are
        // optional so a plain day reads exactly like the original format.
        var extras: [String] = []

        // 1. Long-lived severe alert. Minor/moderate advisories are skipped —
        //    they'd fire most winter mornings and train users to ignore this.
        if let alert = snapshot.alerts.first(where: { $0.severity == .severe || $0.severity == .extreme }) {
            extras.append("Heads up: \(alert.headline).")
        }

        // 2. First precipitation onset in the 12 hours after delivery, when
        //    the delivery hour itself is dry.
        if let onset = Self.precipitationOnsetLine(
            hourly: snapshot.hourly, after: delivery, timezone: snapshot.timezone
        ) {
            extras.append(onset)
        }

        // 3. Big swing vs yesterday's high (compared against the high we
        //    recorded when scheduling yesterday's notification).
        if let swing = temperatureSwingLine(deliveryDayHigh: day?.high, delivery: delivery) {
            extras.append(swing)
        }
        persistDeliveryDayHigh(day?.high, delivery: delivery)

        // 4. Bad air day (Unhealthy or worse).
        if let aqi = snapshot.airQuality, aqi.aqi >= 151 {
            extras.append("Air quality is rough (\(aqi.aqi)). Maybe skip the jog.")
        }

        // Lock-screen surface → same clean-mode rule as widgets. The group
        // phraseMode key already carries the effective widget mode.
        let groupDefaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let mode = PhraseMode(
            rawValue: groupDefaults.string(forKey: AppConstants.UserDefaultsKeys.phraseMode) ?? "clean"
        ) ?? .clean
        // Trim the phrase budget when context lines are present so the body
        // stays readable on the lock screen without truncation.
        let phrase = await phraseEngine.selectPhrase(
            conditionTag: tag,
            tempF: Double(temp),
            mode: mode,
            isDay: hourPoint?.isDay ?? true,
            localHour: deliveryHour,
            maxLength: extras.isEmpty ? 100 : 80,
            trackAsSeen: false
        )

        let extrasText = extras.isEmpty ? "" : extras.joined(separator: " ") + " "
        let content = UNMutableNotificationContent()
        content.title = "Good morning, here's the damn weather"
        content.body = "\(temp)° and \(tag.label.lowercased()). \(highLow)\(extrasText)\(phrase)"
        content.sound = .default

        var trigger = DateComponents()
        trigger.hour = deliveryHour
        trigger.minute = 0
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            morningLog.info("scheduled morning forecast for \(delivery, privacy: .public): \(content.body.prefix(60), privacy: .public)")
        } catch {
            morningLog.error("failed to schedule: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "Rain rolling in around 2 PM." for the first hour within 12 hours of
    /// delivery where precipitation probability crosses 50%. Nil when the
    /// delivery hour is already wet (the condition line covers it) or the
    /// window stays dry.
    private static func precipitationOnsetLine(
        hourly: [HourlyForecastPoint],
        after delivery: Date,
        timezone: TimeZone
    ) -> String? {
        let window = hourly
            .filter { $0.time >= delivery && $0.time <= delivery.addingTimeInterval(12 * 3600) }
            .sorted { $0.time < $1.time }
        guard let deliveryHourPoint = window.first,
              deliveryHourPoint.precipitationProbability < 50 else { return nil }
        guard let start = window.first(where: { $0.precipitationProbability >= 50 }) else { return nil }

        let isSnow = [.snow, .heavySnow, .freezingRain].contains(start.conditionTag)
        let hourLabel = start.time.hourLabel(timezone: timezone)
        return isSnow
            ? "Snow moving in around \(hourLabel)."
            : "Rain rolling in around \(hourLabel)."
    }

    /// "12° colder than yesterday." when the delivery day's high differs from
    /// the previous day's by 10°F or more. Yesterday's high comes from the
    /// value recorded the last time a notification was scheduled — WeatherKit
    /// doesn't return past days, so we remember our own.
    private func temperatureSwingLine(deliveryDayHigh: Double?, delivery: Date) -> String? {
        guard let high = deliveryDayHigh else { return nil }
        let defaults = UserDefaults.standard
        guard let storedDate = defaults.string(forKey: AppConstants.UserDefaultsKeys.morningForecastLastHighDate),
              let storedHigh = defaults.object(forKey: AppConstants.UserDefaultsKeys.morningForecastLastHigh) as? Double,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: delivery),
              storedDate == Self.dayKey(for: yesterday) else { return nil }

        let diff = Int((high - storedHigh).rounded())
        guard abs(diff) >= 10 else { return nil }
        return diff > 0
            ? "\(diff)° warmer than yesterday."
            : "\(abs(diff))° colder than yesterday."
    }

    /// Record the delivery day's forecast high so tomorrow's notification can
    /// compare against it. Same-day re-schedules just overwrite. Must run
    /// AFTER `temperatureSwingLine` reads yesterday's value.
    private func persistDeliveryDayHigh(_ high: Double?, delivery: Date) {
        guard let high else { return }
        let defaults = UserDefaults.standard
        defaults.set(Self.dayKey(for: delivery), forKey: AppConstants.UserDefaultsKeys.morningForecastLastHighDate)
        defaults.set(high, forKey: AppConstants.UserDefaultsKeys.morningForecastLastHigh)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Ask iOS to wake us ~45 minutes before delivery so the content is
    /// fresh. Advisory only — iOS decides if/when it actually runs.
    private func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = nextDeliveryDate().addingTimeInterval(-45 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskSchedulerErrorCodeUnavailable in Simulator, or too many
            // pending requests — both fine, the foreground path still updates.
            morningLog.info("BG refresh submit failed (non-fatal): \(String(describing: error), privacy: .public)")
        }
    }
}
