import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for daily check-in /
/// check-out reminders. Non-isolated because it only touches the system
/// center (thread-safe) and pure-value DTOs.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    private enum Identifier {
        static let checkIn = "daily-check-in"
        static let checkOut = "daily-check-out"
    }

    /// Requests alert+sound+badge authorization. Idempotent — if already
    /// granted / denied, the system returns the cached value without prompt.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Cancels any previously scheduled reminders and installs a fresh pair
    /// for the given times. Repeats daily.
    func scheduleDailyReminders(
        checkIn: (hour: Int, minute: Int),
        checkOut: (hour: Int, minute: Int)
    ) async {
        cancelAll()
        await schedule(
            id: Identifier.checkIn,
            hour: checkIn.hour,
            minute: checkIn.minute,
            title: "Đến giờ chấm công vào",
            body: "Mở ứng dụng và chấm công để bắt đầu ca làm việc."
        )
        await schedule(
            id: Identifier.checkOut,
            hour: checkOut.hour,
            minute: checkOut.minute,
            title: "Nhắc chấm công ra",
            body: "Đừng quên chấm công ra trước khi rời chi nhánh."
        )
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [
            Identifier.checkIn,
            Identifier.checkOut
        ])
    }

    private func schedule(
        id: String,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
