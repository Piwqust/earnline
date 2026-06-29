import Foundation
import SwiftData
import Supabase

@MainActor
enum SyncCoordinator {
    static func sync(context: ModelContext, client: SupabaseClient) async throws -> Date {
        let workspaceID = SupabaseProjectDefaults.workspaceID
        let syncedAt = Date()

        try await pushDeletes(context: context, client: client, workspaceID: workspaceID)
        try await pushLocalRows(context: context, client: client, workspaceID: workspaceID, syncedAt: syncedAt)
        try await pullRemoteRows(context: context, client: client, workspaceID: workspaceID, syncedAt: syncedAt)

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
                                       syncedAt: Date) async throws {
        let remoteClients: [RemoteClient] = try await client
            .from("earnline_clients")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value

        let remoteHeadings: [RemoteHeading] = try await client
            .from("earnline_headings")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value

        let remoteEntries: [RemoteEntry] = try await client
            .from("earnline_entries")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value

        let remoteTombstones: [RemoteTombstone] = try await client
            .from("earnline_tombstones")
            .select()
            .eq("workspace_id", value: workspaceID)
            .execute()
            .value

        let localClients = try context.fetch(FetchDescriptor<Client>())
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

        let localHeadings = try context.fetch(FetchDescriptor<Heading>())
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

        let localEntries = try context.fetch(FetchDescriptor<Entry>())
        var entriesByID = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })

        for record in remoteEntries {
            guard let owner = clientsByID[record.clientID] else { continue }
            let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt)
            if let local = entriesByID[record.id] {
                guard shouldApplyRemote(remoteUpdatedAt: remoteUpdatedAt, localUpdatedAt: local.syncUpdatedAt, localState: local.syncState) else { continue }
                local.amount = Decimal(record.amount)
                local.currencyCode = record.currencyCode
                local.project = record.project
                local.task = record.task
                local.date = SyncDateCodec.parseDay(record.date)
                local.holdUntil = record.holdUntil.map(SyncDateCodec.parseDay)
                local.statusRaw = record.status
                local.sortIndex = record.sortIndex
                local.createdAt = SyncDateCodec.parseTimestamp(record.createdAt)
                local.updatedAt = remoteUpdatedAt
                local.client = owner
                local.markSynced(at: syncedAt)
            } else {
                let entry = Entry(id: record.id,
                                  amount: Decimal(record.amount),
                                  currencyCode: record.currencyCode,
                                  project: record.project,
                                  task: record.task,
                                  date: SyncDateCodec.parseDay(record.date),
                                  holdUntil: record.holdUntil.map(SyncDateCodec.parseDay),
                                  status: EntryStatus(rawValue: record.status) ?? .paid,
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

    private static func shouldApplyRemote(remoteUpdatedAt: Date,
                                          localUpdatedAt: Date,
                                          localState: SyncState) -> Bool {
        localState == .synced || remoteUpdatedAt >= localUpdatedAt
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
