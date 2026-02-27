// meta: created=2026-02-27 updated=2026-02-27 checked=never
import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("[NotificationManager] requestAuthorization failed: %@", "\(error)")
            return false
        }
    }

    func send(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            NSLog("[NotificationManager] send failed (%@): %@", identifier, "\(error)")
        }
    }
}
