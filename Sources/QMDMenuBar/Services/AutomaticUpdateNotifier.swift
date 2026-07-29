import Foundation
@preconcurrency import UserNotifications

enum AutomaticUpdateNotifier {
    static func notifyFailure() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { addFailureNotification() }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                addFailureNotification()
            }
        }
    }

    private static func addFailureNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Agent Memory automatic update failed"
        content.body = "Open Agent Memory for details."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
