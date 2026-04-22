import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter.
///
/// Delivery requires a properly signed app bundle with an `NSUserNotificationUsageDescription`
/// entry and a CFBundleIdentifier. Running via `swift run` from SPM won't deliver notifications;
/// we fall through silently so development remains friction-free. Migrate to an Xcode app
/// target to light this up.
enum NotificationService {
    /// True only when the binary is inside a proper `.app` bundle. The
    /// UserNotifications framework asserts on a real bundleProxy and will crash
    /// an unbundled `swift run` otherwise.
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        guard isBundled else { return }

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
