import Foundation
import UserNotifications
import os.log

nonisolated private let notifLog = Logger(subsystem: "DamnWeather", category: "Notifications")

actor NotificationService {
    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            notifLog.error("permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func scheduleMorningForecast(
        hour: Int = 7,
        minute: Int = 0,
        title: String = "Good morning, here's the damn weather",
        body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "morning-forecast",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            notifLog.error("failed to schedule morning forecast: \(error.localizedDescription, privacy: .public)")
        }
    }

    func sendSevereWeatherAlert(headline: String, description: String) async {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Weather Alert"
        content.subtitle = headline
        content.body = description
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "severe-weather-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            notifLog.error("failed to send severe weather alert: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelMorningForecast() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["morning-forecast"])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
