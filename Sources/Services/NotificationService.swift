import Foundation
import UserNotifications

/// Thin wrapper over local notifications for proactive coaching cues.
/// Used when the user picks "Notifications" (or "Both") as the delivery channel.
@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorized = false

    /// Ask once; safe to call repeatedly.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            authorized = false
        }
    }

    /// Fire a coaching cue immediately as a local notification.
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        // nil trigger = deliver right away.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
