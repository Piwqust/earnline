import Foundation
import SwiftData

/// Moves a guest ("Continue without an account") ledger into the signed-in
/// account store.
///
/// The guest ledger lives in its own SwiftData file (`earnline-production-local-guest`)
/// and never syncs. After a user signs into a real account, this copies those
/// rows into the active account store — preserving each row's identity and
/// marking every copy dirty so the next sync pushes it to the user's Supabase
/// workspace. The guest file is left untouched as a safety net, and importing
/// twice is a no-op: rows whose ids already exist in the destination are
/// skipped, so account data is never overwritten and nothing is duplicated.
@MainActor
enum GuestLedgerMigration {
    struct Summary: Equatable {
        var clients = 0
        var entries = 0
        var headings = 0
        var projectIcons = 0

        var total: Int { clients + entries + headings + projectIcons }
        var isEmpty: Bool { total == 0 }
    }

    /// The guest store's SwiftData file name. This must stay equal to the name
    /// `WorkspaceStore.localStoreName` builds for the fixed guest key
    /// (production · `local-guest` · account). `local-guest` is already
    /// filename-safe, so no sanitizing is needed here; `guestLedgerSummary()`
    /// silently returns empty if the file is ever absent or renamed.
    static let guestStoreName =
        "\(AppModel.WorkspaceEnvironment.production.storeName)-\(AppModel.localGuestWorkspaceID)"

    /// Whether a guest store file exists at all. Checked before opening a
    /// container so a fresh install (or an account-only user who never chose
    /// "Continue without an account") never creates an empty guest store as a
    /// side effect of asking.
    static func guestLedgerExists() -> Bool {
        FileManager.default.fileExists(atPath: guestStoreURL.path)
    }

    /// Counts of what a subsequent import would copy — `.isEmpty` when there is
    /// no guest ledger to bring over, so the UI can hide the action entirely.
    /// Opens (and immediately drops) a throwaway container; call it sparingly.
    static func guestLedgerSummary() -> Summary {
        guard guestLedgerExists(), let container = try? guestContainer() else { return Summary() }
        return counts(in: ModelContext(container))
    }

    /// Open the guest store and copy its rows into `destination`. The guest file
    /// is only read — never modified or deleted.
    @discardableResult
    static func importGuestLedgerFromDisk(into destination: ModelContext) throws -> Summary {
        guard guestLedgerExists() else { return Summary() }
        let source = ModelContext(try guestContainer())
        return try importLedger(from: source, into: destination)
    }

    /// Pure, testable copy: reads every row from `source` and inserts a dirty
    /// copy into `destination`, skipping ids already present there. Ids are
    /// preserved so a row that later arrives through sync merges with its copy
    /// instead of duplicating it. Saves `destination` only when something was
    /// actually inserted.
    @discardableResult
    static func importLedger(from source: ModelContext, into destination: ModelContext) throws -> Summary {
        let sourceClients = try source.fetch(FetchDescriptor<Client>())
        let sourceHeadings = try source.fetch(FetchDescriptor<Heading>())
        let sourceIcons = try source.fetch(FetchDescriptor<ProjectIconPreference>())

        var summary = Summary()

        // Clients first: entries re-link to their owner by id in the destination.
        var destinationClientsByID = Dictionary(
            uniqueKeysWithValues: try destination.fetch(FetchDescriptor<Client>()).map { ($0.id, $0) }
        )
        for client in sourceClients where destinationClientsByID[client.id] == nil {
            let copy = Client(id: client.id,
                              name: client.name,
                              colorHex: client.colorHex,
                              sortIndex: client.sortIndex,
                              createdAt: client.createdAt,
                              updatedAt: client.syncUpdatedAt,
                              syncState: .dirty,
                              lastSyncedAt: nil)
            destination.insert(copy)
            destinationClientsByID[client.id] = copy
            summary.clients += 1
        }

        let existingEntryIDs = Set(try destination.fetch(FetchDescriptor<Entry>()).map(\.id))
        for client in sourceClients {
            guard let owner = destinationClientsByID[client.id] else { continue }
            for entry in client.entries where !existingEntryIDs.contains(entry.id) {
                let copy = Entry(id: entry.id,
                                 amount: entry.amount,
                                 currencyCode: entry.currencyCode,
                                 project: entry.project,
                                 task: entry.task,
                                 date: entry.date,
                                 holdUntil: entry.holdUntil,
                                 status: entry.status,
                                 sortIndex: entry.sortIndex,
                                 createdAt: entry.createdAt,
                                 updatedAt: entry.syncUpdatedAt,
                                 syncState: .dirty,
                                 lastSyncedAt: nil)
                copy.client = owner
                destination.insert(copy)
                summary.entries += 1
            }
        }

        let existingHeadingIDs = Set(try destination.fetch(FetchDescriptor<Heading>()).map(\.id))
        for heading in sourceHeadings where !existingHeadingIDs.contains(heading.id) {
            let copy = Heading(id: heading.id,
                               title: heading.title,
                               date: heading.date,
                               sortIndex: heading.sortIndex,
                               createdAt: heading.createdAt,
                               updatedAt: heading.syncUpdatedAt,
                               syncState: .dirty,
                               lastSyncedAt: nil)
            destination.insert(copy)
            summary.headings += 1
        }

        // Icons are unique on BOTH id and projectKey, so guard both to avoid a
        // unique-constraint insert failure (ids are deterministic from the key,
        // so in practice the two checks agree — the key guard is defensive).
        let destinationIcons = try destination.fetch(FetchDescriptor<ProjectIconPreference>())
        let existingIconIDs = Set(destinationIcons.map(\.id))
        let existingIconKeys = Set(destinationIcons.map(\.projectKey))
        for icon in sourceIcons
        where !existingIconIDs.contains(icon.id) && !existingIconKeys.contains(icon.projectKey) {
            let copy = ProjectIconPreference(id: icon.id,
                                             projectKey: icon.projectKey,
                                             symbol: icon.symbol,
                                             createdAt: icon.createdAt,
                                             updatedAt: icon.syncUpdatedAt,
                                             syncState: .dirty,
                                             lastSyncedAt: nil)
            destination.insert(copy)
            summary.projectIcons += 1
        }

        if !summary.isEmpty {
            try destination.save()
        }
        return summary
    }

    private static func counts(in context: ModelContext) -> Summary {
        Summary(
            clients: (try? context.fetchCount(FetchDescriptor<Client>())) ?? 0,
            entries: (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0,
            headings: (try? context.fetchCount(FetchDescriptor<Heading>())) ?? 0,
            projectIcons: (try? context.fetchCount(FetchDescriptor<ProjectIconPreference>())) ?? 0
        )
    }

    /// SwiftData stores a named configuration at
    /// `Library/Application Support/<name>.store`.
    private static var guestStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(guestStoreName).store")
    }

    private static func guestContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EarnlineSchemaV2.self)
        let configuration = ModelConfiguration(guestStoreName, schema: schema)
        return try ModelContainer(for: schema,
                                  migrationPlan: EarnlineMigrationPlan.self,
                                  configurations: configuration)
    }
}
