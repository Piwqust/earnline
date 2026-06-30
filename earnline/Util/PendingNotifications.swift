import Foundation
import UserNotifications

/// Local reminders for in-progress lines that carry a `holdUntil` date.
///
/// The scheduler is *recompute-only*: `sync` clears every pending request and
/// rebuilds from the current entries, so there's no delta tracking — calling it
/// after any save point keeps the schedule correct. The pure `desiredRequests`
/// step is unit-tested; the `UNUserNotificationCenter` plumbing is not.
enum PendingNotifications {
    /// One reminder we want scheduled.
    struct Request: Equatable {
        let id: String              // entry.id.uuidString — stable, so rebuilds are idempotent
        let dateComponents: DateComponents
        let body: String
    }

    /// The reminders we want for the given entries: one per in-progress line with
    /// a `holdUntil` that is today or later, fired at 09:00 local on that day.
    /// Past-due holds get nothing here (they surface in-app in the Pending view).
    static func desiredRequests(for entries: [Entry],
                                now: Date = .now,
                                calendar: Calendar = .current) -> [Request] {
        let today = calendar.startOfDay(for: now)
        return entries.compactMap { entry in
            guard entry.status == .inProgress, let hold = entry.holdUntil else { return nil }
            let holdDay = calendar.startOfDay(for: hold)
            guard holdDay >= today else { return nil }

            var components = calendar.dateComponents([.year, .month, .day], from: holdDay)
            components.hour = 9

            let client = entry.client?.name ?? "Income"
            let detail = entry.task.isEmpty ? (entry.project ?? "line") : entry.task
            return Request(id: entry.id.uuidString,
                           dateComponents: components,
                           body: "\(client) · \(detail) is due — mark it paid?")
        }
    }

    /// Ask once for permission (alert + sound). Safe to call repeatedly.
    static func requestAuthorization(center: UNUserNotificationCenter = .current()) async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Clear and rebuild all pending reminders from `entries`.
    static func sync(_ entries: [Entry], center: UNUserNotificationCenter = .current()) {
        let requests = desiredRequests(for: entries)
        center.removeAllPendingNotificationRequests()
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = "Income due"
            content.body = request.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: request.dateComponents, repeats: false)
            center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
        }
    }
}
