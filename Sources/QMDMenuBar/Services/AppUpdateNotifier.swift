import Foundation
@preconcurrency import UserNotifications

enum AppUpdateNotifier {
    static func notifyAvailable(_ update: AppUpdate) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { addNotification(update) }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                addNotification(update)
            }
        }
    }

    private static func addNotification(_ update: AppUpdate) {
        let content = UNMutableNotificationContent()
        content.title = "Agent Memory update available"
        content.body = "\(update.summary) (\(update.displayBuild))"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "AgentMemory.app-update.\(update.identifier)",
                content: content,
                trigger: nil
            )
        )
    }
}
