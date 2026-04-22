import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter.
///
/// Delivery requires a properly signed app bundle with an `NSUserNotificationUsageDescription`
/// entry and a CFBundleIdentifier. Running via `swift run` from SPM won't deliver notifications;
/// we fall through silently so development remains friction-free. Migrate to an Xcode app
/// target to light this up.
enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
