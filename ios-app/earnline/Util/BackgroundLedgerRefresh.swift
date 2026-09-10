import BackgroundTasks
import OSLog
import UIKit

@MainActor
enum BackgroundLedgerRefresh {
    static let identifier = "com.earnline.app.refresh"
    private static var registered = false
    private static let logger = Logger(subsystem: "com.earnline.app", category: "background-refresh")

    static func cancel() {
        guard registered else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    static func register() {
        guard !registered, !AppModel.isRunningUIAutomation, !AppModel.isRunningUnitTests,
              !AppModel.isLocalOnlyDevBuild else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let work = Task { @MainActor in
                guard let app = EarnlineRuntime.shared.app else {
                    task.setTaskCompleted(success: false)
                    return
                }
                defer { scheduleIfNeeded(app: app) }
                // No new authentication prompts or Keychain-policy changes in
                // the background. A locked device retries on foreground entry.
                guard UIApplication.shared.isProtectedDataAvailable,
                      app.isSupabaseConfigured, !app.isSyncing else {
                    task.setTaskCompleted(success: false)
                    return
                }
                do {
                    let (_, context) = try EarnlineRuntime.shared.ledger()
                    try Task.checkCancellation()
                    let error = await app.syncNow(context: context)
                    task.setTaskCompleted(success: error == nil && !Task.isCancelled)
                } catch {
                    task.setTaskCompleted(success: false)
                }
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleIfNeeded(app: AppModel) {
        guard registered, app.isSupabaseConfigured else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.info("Background refresh unavailable: \(error.localizedDescription, privacy: .private)")
        }
    }
}
