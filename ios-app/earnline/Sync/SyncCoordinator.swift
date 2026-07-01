import Foundation
import SwiftData
import Supabase

@MainActor
enum SyncCoordinator {
    private static let tombstoneRetentionDays = 90

    static func sync(context: ModelContext,
                     client: SupabaseClient,
                     workspaceID: String,
                     lastPulledAt: Date? = nil) async throws -> Date {
        let syncedAt = Date()

        // Push tombstones before pulling rows: in this personal no-login model,
        // a local delete intentionally wins over a concurrent remote update.
        try await pushDeletes(context: context, client: client, workspaceID: workspaceID)
        try await pushLocalRows(context: context, client: client, workspaceID: workspaceID, syncedAt: syncedAt)
        try await pullRemoteRows(context: context,
                                 client: client,
                                 workspaceID: workspaceID,
                                 lastPulledAt: lastPulledAt,
                                 syncedAt: syncedAt)
        await pruneRemoteTombstones(client: client, workspaceID: workspaceID, syncedAt: syncedAt)

        try context.save()
        return syncedAt
    }

    private static func pushDeletes(context: ModelContext, client: SupabaseClient, workspaceID: String) async throws {
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        guard !tombstones.isEmpty else { return }

        let remoteTombstones = tombstones.map { RemoteTombstone($0, workspaceID: workspaceID) }
        try await client
            .from("earnline_tombstones")
            .upsert(remoteTombstones)
            .execute()

        for tombstone in tombstones {
            try await client
                .from(tableName(for: tombstone.entity))
                .delete()
                .eq("id", value: tombstone.recordID.uuidString)
                .eq("workspace_id", value: workspaceID)
                .execute()
            context.delete(tombstone)
        }
    }

    private static func pushLocalRows(context: ModelContext,
                                      client: SupabaseClient,
                                      workspaceID: String,
                                      syncedAt: Date) async throws {
        let clients = try context.fetch(FetchDescriptor<Client>())
        let headings = try context.fetch(FetchDescriptor<Heading>())
        let entries = try context.fetch(FetchDescriptor<Entry>())

        let dirtyClients = clients.filter(\.needsSync).map { RemoteClient($0, workspaceID: workspaceID) }
        if !dirtyClients.isEmpty {
            try await client.from("earnline_clients").upsert(dirtyClients).execute()
            clients.filter(\.needsSync).forEach { $0.markSynced(at: syncedAt) }
        }

        let dirtyHeadings = headings.filter(\.needsSync).map { RemoteHeading($0, workspaceID: workspaceID) }
        if !dirtyHeadings.isEmpty {
            try await client.from("earnline_headings").upsert(dirtyHeadings).execute()
            headings.filter(\.needsSync).forEach { $0.markSynced(at: syncedAt) }
        }

        let dirtyEntries = entries.filter(\.needsSync).compactMap { RemoteEntry($0, workspaceID: workspaceID) }
        if !dirtyEntries.isEmpty {
            try await client.from("earnline_entries").upsert(dirtyEntries).execute()
            entries.filter(\.needsSync).forEach { $0.markSynced(at: syncedAt) }
        }
    }

    private static func pullRemoteRows(context: ModelContext,
                                       client: SupabaseClient,
                                       workspaceID: String,
                                       lastPulledAt: Date?,
                                       syncedAt: Date) async throws {
        let localClients = try context.fetch(FetchDescriptor<Client>())
        let localHeadings = try context.fetch(FetchDescriptor<Heading>())
        let localEntries = try context.fetch(FetchDescriptor<Entry>())

        let clientSince = localClients.isEmpty ? nil : lastPulledAt
        let headingSince = localHeadings.isEmpty ? nil : lastPulledAt
        let entrySince = localEntries.isEmpty ? nil : lastPulledAt

        let remoteClients = try await fetchClients(client: client, workspaceID: workspaceID, updatedAfter: clientSince)
        let remoteHeadings = try await fetchHeadings(client: client, workspaceID: workspaceID, updatedAfter: headingSince)
        let remoteEntries = try await fetchEntries(client: client, workspaceID: workspaceID, updatedAfter: entrySince)
        let remoteTombstones = try await fetchTombstones(client: client, workspaceID: workspaceID, deletedAfter: lastPulledAt)

        var clientsByID = Dictionary(uniqueKeysWithValues: localClients.map { ($0.id, $0) })

        for record in remoteClients {
            let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt)
            if let local = clientsByID[record.id] {
                guard shouldApplyRemote(remoteUpdatedAt: remoteUpdatedAt, localUpdatedAt: local.syncUpdatedAt, localState: local.syncState) else { continue }
                local.name = record.name
                local.colorHex = record.colorHex
                local.sortIndex = record.sortIndex
                local.createdAt = SyncDateCodec.parseTimestamp(record.createdAt)
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: syncedAt)
            } else {
                let newClient = Client(id: record.id,
                                       name: record.name,
                                       colorHex: record.colorHex,
                                       sortIndex: record.sortIndex,
                                       createdAt: SyncDateCodec.parseTimestamp(record.createdAt),
                                       updatedAt: remoteUpdatedAt,
                                       syncState: .synced,
                                       lastSyncedAt: syncedAt)
                context.insert(newClient)
                clientsByID[record.id] = newClient
            }
        }

        var headingsByID = Dictionary(uniqueKeysWithValues: localHeadings.map { ($0.id, $0) })

        for record in remoteHeadings {
            let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt)
            if let local = headingsByID[record.id] {
                guard shouldApplyRemote(remoteUpdatedAt: remoteUpdatedAt, localUpdatedAt: local.syncUpdatedAt, localState: local.syncState) else { continue }
                local.title = record.title
                local.date = SyncDateCodec.parseDay(record.date)
                local.sortIndex = record.sortIndex
                local.createdAt = SyncDateCodec.parseTimestamp(record.createdAt)
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: syncedAt)
            } else {
                let heading = Heading(id: record.id,
                                      title: record.title,
                                      date: SyncDateCodec.parseDay(record.date),
                                      sortIndex: record.sortIndex,
                                      createdAt: SyncDateCodec.parseTimestamp(record.createdAt),
                                      updatedAt: remoteUpdatedAt,
                                      syncState: .synced,
                                      lastSyncedAt: syncedAt)
                context.insert(heading)
                headingsByID[record.id] = heading
            }
        }

        var entriesByID = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })

        for record in remoteEntries {
            guard let owner = clientsByID[record.clientID] else { continue }
            let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt)
            if let local = entriesByID[record.id] {
                guard shouldApplyRemote(remoteUpdatedAt: remoteUpdatedAt, localUpdatedAt: local.syncUpdatedAt, localState: local.syncState) else { continue }
                local.amount = record.amount.decimal
                local.currencyCode = record.currencyCode
                local.project = record.project
                local.task = record.task
                local.date = SyncDateCodec.parseDay(record.date)
                local.holdUntil = record.holdUntil.map(SyncDateCodec.parseDay)
                local.statusRaw = EntryStatus.fromSyncRawValue(record.status).rawValue
                local.sortIndex = record.sortIndex
                local.createdAt = SyncDateCodec.parseTimestamp(record.createdAt)
                local.updatedAt = remoteUpdatedAt
                local.client = owner
                local.markSynced(at: syncedAt)
            } else {
                let entry = Entry(id: record.id,
                                  amount: record.amount.decimal,
                                  currencyCode: record.currencyCode,
                                  project: record.project,
                                  task: record.task,
                                  date: SyncDateCodec.parseDay(record.date),
                                  holdUntil: record.holdUntil.map(SyncDateCodec.parseDay),
                                  status: EntryStatus.fromSyncRawValue(record.status),
                                  sortIndex: record.sortIndex,
                                  createdAt: SyncDateCodec.parseTimestamp(record.createdAt),
                                  updatedAt: remoteUpdatedAt,
                                  syncState: .synced,
                                  lastSyncedAt: syncedAt)
                entry.client = owner
                context.insert(entry)
                entriesByID[record.id] = entry
            }
        }

        try applyRemoteTombstones(remoteTombstones,
                                  clientsByID: clientsByID,
                                  headingsByID: headingsByID,
                                  entriesByID: entriesByID,
                                  context: context)
    }

    private static func applyRemoteTombstones(_ records: [RemoteTombstone],
                                              clientsByID: [UUID: Client],
                                              headingsByID: [UUID: Heading],
                                              entriesByID: [UUID: Entry],
                                              context: ModelContext) throws {
        for record in records {
            guard let entity = SyncEntity(rawValue: record.entity) else { continue }
            let deletedAt = SyncDateCodec.parseTimestamp(record.deletedAt)
            switch entity {
            case .client:
                if let client = clientsByID[record.recordID], deletedAt >= client.syncUpdatedAt {
                    context.delete(client)
                }
            case .heading:
                if let heading = headingsByID[record.recordID], deletedAt >= heading.syncUpdatedAt {
                    context.delete(heading)
                }
            case .entry:
                if let entry = entriesByID[record.recordID], deletedAt >= entry.syncUpdatedAt {
                    context.delete(entry)
                }
            }
        }
    }

    /// Conflict policy (last-write-wins, with local edits protected):
    /// - If the local row has no unsynced edits (`.synced`), always take the
    ///   remote copy — there's nothing local worth keeping.
    /// - If the local row is dirty, take the remote copy only when it is at least
    ///   as new as the local edit (`remote >= local`); a strictly newer local
    ///   edit wins. Equal timestamps resolve in favour of remote.
    /// Deletes are not handled here — tombstones are pushed before this pull
    /// (`sync`), so a local delete always wins over a concurrent remote update.
    /// `updated_at` is server-authoritative (DB trigger) to keep this ordering
    /// stable across devices regardless of client clock skew.
    static func shouldApplyRemote(remoteUpdatedAt: Date,
                                  localUpdatedAt: Date,
                                  localState: SyncState) -> Bool {
        localState == .synced || remoteUpdatedAt >= localUpdatedAt
    }

    private static func fetchClients(client: SupabaseClient,
                                     workspaceID: String,
                                     updatedAfter: Date?) async throws -> [RemoteClient] {
        if let updatedAfter {
            return try await client
                .from("earnline_clients")
                .select()
                .eq("workspace_id", value: workspaceID)
                .gte("updated_at", value: SyncDateCodec.timestampString(updatedAfter))
                .execute()
                .value
        }
        return try await client
            .from("earnline_clients")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value
    }

    private static func fetchHeadings(client: SupabaseClient,
                                      workspaceID: String,
                                      updatedAfter: Date?) async throws -> [RemoteHeading] {
        if let updatedAfter {
            return try await client
                .from("earnline_headings")
                .select()
                .eq("workspace_id", value: workspaceID)
                .gte("updated_at", value: SyncDateCodec.timestampString(updatedAfter))
                .execute()
                .value
        }
        return try await client
            .from("earnline_headings")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value
    }

    private static func fetchEntries(client: SupabaseClient,
                                     workspaceID: String,
                                     updatedAfter: Date?) async throws -> [RemoteEntry] {
        if let updatedAfter {
            return try await client
                .from("earnline_entries")
                .select()
                .eq("workspace_id", value: workspaceID)
                .gte("updated_at", value: SyncDateCodec.timestampString(updatedAfter))
                .execute()
                .value
        }
        return try await client
            .from("earnline_entries")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value
    }

    private static func fetchTombstones(client: SupabaseClient,
                                        workspaceID: String,
                                        deletedAfter: Date?) async throws -> [RemoteTombstone] {
        if let deletedAfter {
            return try await client
                .from("earnline_tombstones")
                .select()
                .eq("workspace_id", value: workspaceID)
                .gte("deleted_at", value: SyncDateCodec.timestampString(deletedAfter))
                .execute()
                .value
        }
        return try await client
            .from("earnline_tombstones")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value
    }

    private static func pruneRemoteTombstones(client: SupabaseClient,
                                              workspaceID: String,
                                              syncedAt: Date) async {
        guard let cutoff = Calendar.current.date(byAdding: .day,
                                                 value: -tombstoneRetentionDays,
                                                 to: syncedAt) else { return }
        do {
            try await client
                .from("earnline_tombstones")
                .delete()
                .eq("workspace_id", value: workspaceID)
                .lt("deleted_at", value: SyncDateCodec.timestampString(cutoff))
                .execute()
        } catch {
            // Tombstone pruning is retention hygiene; row push/pull already succeeded.
        }
    }

    private static func tableName(for entity: SyncEntity) -> String {
        switch entity {
        case .client:
            return "earnline_clients"
        case .entry:
            return "earnline_entries"
        case .heading:
            return "earnline_headings"
        }
    }
}
