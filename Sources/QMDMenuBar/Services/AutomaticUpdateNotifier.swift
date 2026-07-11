import Foundation
@preconcurrency import UserNotifications

enum AutomaticUpdateNotifier {
    static func notifyFailure(_ message: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { addFailureNotification(message) }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                addFailureNotification(message)
            }
        }
    }

    private static func addFailureNotification(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "QMD automatic update failed"
        content.body = String(message.prefix(500))
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
