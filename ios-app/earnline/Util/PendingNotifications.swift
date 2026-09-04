import Foundation
import OSLog
import UserNotifications

/// Local reminders for in-progress lines that carry a `holdUntil` date.
///
/// The scheduler is *recompute-only*: `sync` derives the wanted reminders from
/// the current entries and reconciles the notification center against them —
/// removing stale requests and adding missing ones, leaving matching requests
/// untouched. The pure `desiredRequests` step is unit-tested; the
/// `UNUserNotificationCenter` plumbing is not.
enum PendingNotifications {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.earnline.app",
        category: "notifications"
    )
    /// One reminder we want scheduled.
    struct Request: Equatable, Sendable {
        let id: String              // entry.id.uuidString — stable, so rebuilds are idempotent
        let dateComponents: DateComponents
        let body: String
    }

    /// The reminders we want for the given entries: one per in-progress line
    /// with a future `holdUntil`, fired at 09:00 local on that day. Past-due
    /// holds get nothing here (they surface in-app in the Pending view), and
    /// neither does a hold due today once 09:00 has passed — a past calendar
    /// trigger fires immediately, and every rebuild would fire it again.
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
            guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

            let client = entry.client?.name ?? String(localized: "Income")
            let detail = entry.task.isEmpty ? (entry.project ?? String(localized: "line")) : entry.task
            return Request(id: entry.id.uuidString,
                           dateComponents: components,
                           body: String(localized: "\(client) · \(detail) is due — mark it paid?"))
        }
    }

    /// Ask once for permission (alert + sound). Safe to call repeatedly.
    @discardableResult
    static func requestAuthorization(center: UNUserNotificationCenter = .current()) async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Reconcile scheduled reminders with `entries`. Permission is requested
    /// lazily, the first time there is actually something to schedule — so the
    /// prompt appears in context (setting a hold date) rather than at launch.
    static func sync(_ entries: [Entry]) {
        let desired = desiredRequests(for: entries)
        // The center is obtained inside the task: UNUserNotificationCenter is
        // not Sendable, so it must not be captured across the Task boundary.
        Task {
            do {
                try await reconcile(desired, center: .current())
            } catch {
                logger.error("Notification reconciliation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func reconcile(_ desired: [Request], center: UNUserNotificationCenter) async throws {
        if !desired.isEmpty {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard await requestAuthorization(center: center) else { return }
            } else if settings.authorizationStatus == .denied {
                logger.info("Notifications are disabled; keeping existing requests unchanged")
                return
            }
        }

        let pending = await center.pendingNotificationRequests()
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
        var unchanged = Set<String>()
        var stale: [String] = []
        for request in pending {
            if let want = desiredByID[request.identifier], matches(request, want) {
                unchanged.insert(request.identifier)
            } else {
                stale.append(request.identifier)
            }
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for want in desired where !unchanged.contains(want.id) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Income due")
            content.body = want.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: want.dateComponents, repeats: false)
            try await center.add(UNNotificationRequest(identifier: want.id, content: content, trigger: trigger))
        }
    }

    private static func matches(_ request: UNNotificationRequest, _ want: Request) -> Bool {
        guard request.content.body == want.body,
              let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        let scheduled = trigger.dateComponents
        return scheduled.year == want.dateComponents.year
            && scheduled.month == want.dateComponents.month
            && scheduled.day == want.dateComponents.day
            && scheduled.hour == want.dateComponents.hour
    }
}
