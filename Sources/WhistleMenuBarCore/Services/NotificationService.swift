import Foundation
import UserNotifications

public final class NotificationService {
    private let center: UNUserNotificationCenter
    private let unavailableHandler: () -> Void

    public init(
        center: UNUserNotificationCenter = .current(),
        unavailableHandler: @escaping () -> Void = {}
    ) {
        self.center = center
        self.unavailableHandler = unavailableHandler
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
        let unavailableHandler = unavailableHandler
        center.getNotificationSettings { [center, unavailableHandler] settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                unavailableHandler()
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
