import CoreSpotlight
import SwiftData
import UniformTypeIdentifiers
import WidgetKit
import OSLog

@MainActor
enum LedgerSystemSurfaces {
    static let spotlightPreference = "spotlightEnabled"
    private static var indexWorker: Task<Void, Never>?
    private static var revision = 0
    private static let logger = Logger(subsystem: "com.earnline.app", category: "system-surfaces")
    private static let index = CSSearchableIndex(name: "earnline-ledger")

    static func refresh(app: AppModel, context: ModelContext) async {
        guard !AppModel.isLocalOnlyDevBuild else { return }
        // Privacy changes must clear old content even if the local store cannot be read.
        guard app.isAccountReady, !app.requireAppLock else { hide(); return }
        do {
            let month = DateFormat.monthStart(of: .now)
            let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? .distantFuture
            let rows = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= month && $0.date < end }))
            let total = rows.filter { !$0.isInvalidated && $0.status.isIncludedInEarnedTotals }
                .reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
            try LedgerWidgetSnapshot(date: .now, month: DateFormat.monthAndYear(month),
                primary: app.primaryString(total),
                secondary: app.secondaryString(total), hidesAmounts: false).write()
            WidgetCenter.shared.reloadTimelines(ofKind: "earnline.earnings")
            guard app.defaults.bool(forKey: spotlightPreference) else {
                scheduleIndex([], identity: app.workspaceStoreIdentity, app: app)
                return
            }
            let identity = app.workspaceStoreIdentity
            let entries = try context.fetch(FetchDescriptor<Entry>())
            let items = entries.filter { !$0.isInvalidated }.map { entry in
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = entry.task
                attributes.contentDescription = [entry.client?.name, entry.project].compactMap { $0 }.joined(separator: " · ")
                attributes.contentCreationDate = entry.date
                return CSSearchableItem(uniqueIdentifier: "\(identity)|\(entry.id.uuidString)",
                                        domainIdentifier: "earnline-ledger", attributeSet: attributes)
            }
            scheduleIndex(items, identity: identity, app: app)
        } catch {
            hide()
            logger.error("Could not refresh system surfaces: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func hide() {
        guard !AppModel.isLocalOnlyDevBuild else { return }
        do {
            try LedgerWidgetSnapshot(date: .now, month: "", primary: "", secondary: "", hidesAmounts: true).write()
        } catch {
            if let directory = LedgerWidgetSnapshot.directory {
                do {
                    try FileManager.default.removeItem(at: directory.appendingPathComponent(LedgerWidgetSnapshot.fileName))
                } catch {
                    logger.error("Could not clear widget snapshot: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "earnline.earnings")
        scheduleIndex([], identity: "", app: nil)
    }

    private static func scheduleIndex(_ items: [CSSearchableItem], identity: String, app: AppModel?) {
        revision &+= 1
        let stamp = revision
        let previous = indexWorker
        indexWorker = Task {
            await previous?.value
            guard stamp == revision else { return }
            do {
                try await index.deleteAllSearchableItems()
                guard stamp == revision, let app, app.isAccountReady, !app.requireAppLock,
                      app.workspaceStoreIdentity == identity,
                      app.defaults.bool(forKey: spotlightPreference), !items.isEmpty else { return }
                try await index.indexSearchableItems(items)
            } catch {
                logger.error("Could not update Spotlight: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    static func sharedText() -> String? {
        guard !AppModel.isLocalOnlyDevBuild, let root = LedgerWidgetSnapshot.directory?.appendingPathComponent("share-inbox"),
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
              let file = files.filter({ $0.pathExtension == "txt" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        // Remove only after the user imports or explicitly discards the draft.
        return text
    }

    static func consumeSharedText(_ text: String) {
        guard !AppModel.isLocalOnlyDevBuild, let root = LedgerWidgetSnapshot.directory?.appendingPathComponent("share-inbox"),
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where (try? String(contentsOf: file, encoding: .utf8)) == text { try? FileManager.default.removeItem(at: file) }
    }
}
