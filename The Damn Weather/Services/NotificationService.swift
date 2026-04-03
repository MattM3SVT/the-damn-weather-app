import Foundation
import UserNotifications

actor NotificationService {
    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
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

        try? await UNUserNotificationCenter.current().add(request)
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

        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelMorningForecast() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["morning-forecast"])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
