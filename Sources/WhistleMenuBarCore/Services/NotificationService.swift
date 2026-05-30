import AppKit
import Foundation
import UserNotifications

public final class NotificationService {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.warn("Notification authorization failed: \(error)")
            } else if !granted {
                Log.info("Notification authorization denied")
            }
        }
    }

    public func send(titleKey: String, bodyKey: String) {
        send(title: L10n.string(titleKey), body: L10n.string(bodyKey))
    }

    public func send(titleKey: String, body: String) {
        send(title: L10n.string(titleKey), body: body)
    }

    public func send(title: String, body: String) {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                NSSound.beep()
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "whistle-menubar-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error {
                    Log.warn("Failed to deliver notification: \(error)")
                }
            }
        }
    }
}
