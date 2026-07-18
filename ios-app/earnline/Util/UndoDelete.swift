import Foundation
import SwiftData

/// Value snapshots of just-deleted rows, staged briefly (`AppModel.stageUndo`)
/// so an accidental swipe can be reversed. Captured BEFORE the models are
/// deleted — a SwiftData model is unusable once removed from its context.
struct EntrySnapshot {
    let id: UUID
    let amount: Decimal
    let currencyCode: String
    let project: String?
    let task: String
    let date: Date
    let holdUntil: Date?
    let statusRaw: String
    let sortIndex: Int
    let createdAt: Date
    let clientID: UUID?

    init(_ entry: Entry) {
        id = entry.id
        amount = entry.amount
        currencyCode = entry.currencyCode
        project = entry.project
        task = entry.task
        date = entry.date
        holdUntil = entry.holdUntil
        statusRaw = entry.statusRaw
        sortIndex = entry.sortIndex
        createdAt = entry.createdAt
        clientID = entry.client?.id
    }
}

struct HeadingSnapshot {
    let id: UUID
    let title: String
    let date: Date
    let sortIndex: Int
    let createdAt: Date

    init(_ heading: Heading) {
        id = heading.id
        title = heading.title
        date = heading.date
        sortIndex = heading.sortIndex
        createdAt = heading.createdAt
    }
}

struct ClientSnapshot {
    let id: UUID
    let name: String
    let colorHex: String
    let sortIndex: Int
    let createdAt: Date
    let entries: [EntrySnapshot]

    init(_ client: Client) {
        id = client.id
        name = client.name
        colorHex = client.colorHex
        sortIndex = client.sortIndex
        createdAt = client.createdAt
        entries = client.entries.map(EntrySnapshot.init)
    }
}

enum UndoableDelete {
    case entry(EntrySnapshot)
    case heading(HeadingSnapshot)
    case client(ClientSnapshot)

    /// Re-insert the snapshot with its ORIGINAL id as a dirty row (fresh
    /// `updatedAt`) and drop the matching local tombstone. If the debounced
    /// sync already pushed the tombstone, the restore still wins everywhere:
    /// the re-pushed row's server-set `updated_at` lands after the tombstone's
    /// `deleted_at`, so the tombstone-apply guard (`deletedAt >=
    /// syncUpdatedAt` in `SyncCoordinator.applyRemoteTombstones`) skips it,
    /// and peer devices re-pull the row in the same pass that delivers the
    /// tombstone.
    func restore(in context: ModelContext) throws {
        switch self {
        case .entry(let snapshot):
            try restoreEntry(snapshot, in: context)
        case .heading(let snapshot):
            try SyncDeleteQueue.dequeue(.heading, id: snapshot.id, in: context)
            context.insert(Heading(id: snapshot.id,
                                   title: snapshot.title,
                                   date: snapshot.date,
                                   sortIndex: snapshot.sortIndex,
                                   createdAt: snapshot.createdAt))
        case .client(let snapshot):
            try SyncDeleteQueue.dequeue(.client, id: snapshot.id, in: context)
            let client = Client(id: snapshot.id,
                                name: snapshot.name,
                                colorHex: snapshot.colorHex,
                                sortIndex: snapshot.sortIndex,
                                createdAt: snapshot.createdAt)
            context.insert(client)
            for entry in snapshot.entries {
                insert(entry, into: client, context: context)
            }
        }
    }

    private func restoreEntry(_ snapshot: EntrySnapshot, in context: ModelContext) throws {
        try SyncDeleteQueue.dequeue(.entry, id: snapshot.id, in: context)
        // Reattach to the owning client; if that client vanished in the
        // meantime (deleted on another device), there is nothing to restore
        // into — an orphan row would never render or sync.
        guard let clientID = snapshot.clientID else { return }
        // Whole-table scan on purpose — see SyncDeleteQueue.dequeue.
        let owner = try context.fetch(FetchDescriptor<Client>()).first { $0.id == clientID }
        guard let owner else { return }
        insert(snapshot, into: owner, context: context)
    }

    private func insert(_ snapshot: EntrySnapshot, into client: Client, context: ModelContext) {
        let entry = Entry(id: snapshot.id,
                          amount: snapshot.amount,
                          currencyCode: snapshot.currencyCode,
                          project: snapshot.project,
                          task: snapshot.task,
                          date: snapshot.date,
                          holdUntil: snapshot.holdUntil,
                          status: EntryStatus.fromSyncRawValue(snapshot.statusRaw),
                          sortIndex: snapshot.sortIndex,
                          createdAt: snapshot.createdAt)
        entry.client = client
        context.insert(entry)
    }
}
