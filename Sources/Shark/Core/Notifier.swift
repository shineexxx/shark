import Foundation
@preconcurrency import UserNotifications

/// Уведомления о завершении очереди. Разрешение спрашиваем лениво —
/// только когда пользователь включил соответствующую настройку.
enum Notifier {

    static func post(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
                  granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
