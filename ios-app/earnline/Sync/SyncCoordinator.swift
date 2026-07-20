import Foundation
import SwiftData
import Supabase

@MainActor
enum SyncCoordinator {
    private static let pageSize = 1000

    /// A dirty local row and a newer remote row are a real user decision, not a
    /// timestamp race to resolve silently. The normal pass stops before either
    /// version is overwritten; Settings can explicitly retry with the local
    /// choice when that is what the user intends.
    enum ConflictResolution {
        case requireUserChoice
        case preferLocal
    }

    enum SyncConflictError: LocalizedError, Equatable {
        case detected(Int)

        var count: Int {
            switch self {
            case .detected(let count): count
            }
        }

        var errorDescription: String? {
            switch self {
            case .detected(let count):
                let noun = count == 1 ? "change" : "changes"
                return "Cloud data changed while this iPhone had \(count) unsynced \(noun). Choose which copy to keep before syncing."
            }
        }
    }

    /// The row cursor is sourced only from server-managed `updated_at` values.
    /// Tombstones are replayed in full because their deletion date originates
    /// on a device and cannot safely act as an incremental cursor.
    struct SyncCursor: Equatable {
        let rowUpdatedAt: Date?
    }

    /// Synchronize the single workspace profile. A locally edited currency
    /// tuple wins on the next pass; otherwise the cloud copy is applied. When
    /// the row does not exist yet, the current device seeds it.
    static func syncWorkspaceProfile(client: SupabaseClient,
                                     workspaceID: String,
                                     local: WorkspaceProfilePayload,
                                     pushLocal: Bool) async throws -> RemoteWorkspaceProfile {
        let remote: [RemoteWorkspaceProfile] = try await client
            .from("earnline_profiles")
            .select()
            .eq("workspace_id", value: workspaceID)
            .limit(1)
            .execute()
            .value

        if !pushLocal, let existing = remote.first {
            return existing
        }

        return try await client
            .from("earnline_profiles")
            .upsert(local, onConflict: "workspace_id")
            .select()
            .single()
            .execute()
            .value
    }

    /// Runs a full sync pass and returns the server-managed row cursor.
    /// Tombstones are paged and reapplied on every pass so a skewed device clock
    /// can never hide a remote deletion. `gte` makes row cursor boundaries
    /// idempotent to reapply.
    static func sync(context: ModelContext,
                     client: SupabaseClient,
                     workspaceID: String,
                     lastPulledAt: Date? = nil,
                     conflictResolution: ConflictResolution = .requireUserChoice) async throws -> SyncCursor {
        // Push tombstones before pulling rows: in this personal no-login model,
        // a local delete intentionally wins over a concurrent remote update.
        try await pushDeletes(context: context, client: client, workspaceID: workspaceID)

        // Apply remote deletes *before* pushing rows: a client deleted on
        // another device must take its local entries with it now — otherwise
        // pushing those entries hits the remote FK (their client row is gone),
        // the sync throws before the tombstone pull, and every retry wedges
        // the same way.
        let remoteTombstones = try await fetchTombstones(client: client,
                                                         workspaceID: workspaceID,
                                                         deletedAfter: nil)
        try applyRemoteTombstones(remoteTombstones,
                                  context: context,
                                  conflictResolution: conflictResolution)

        // Pull before normal row pushes. A previous version pushed first, which
        // made the local device that happened to reconnect last overwrite a
        // remote edit before conflict detection ever ran.
        let maxRowUpdatedAt = try await pullRemoteRows(context: context,
                                                       client: client,
                                                       workspaceID: workspaceID,
                                                       lastPulledAt: lastPulledAt,
                                                       conflictResolution: conflictResolution)
        // Materialize remote cascade deletes before pushing rows so an entry
        // whose client vanished remotely cannot violate the remote FK.
        try context.save()

        try await pushLocalRows(context: context,
                                client: client,
                                workspaceID: workspaceID)

        // Read the server-written `updated_at` values for rows just pushed.
        // A device clock is not a valid conflict baseline: if this refresh is
        // interrupted, the row deliberately keeps a nil baseline and a later
        // concurrent edit requires a user choice instead of being overwritten.
        let maxRowUpdatedAfterPush = try await pullRemoteRows(context: context,
                                                              client: client,
                                                              workspaceID: workspaceID,
                                                              lastPulledAt: lastPulledAt,
                                                              conflictResolution: conflictResolution)

        try context.save()

        let newestRow = [maxRowUpdatedAt, maxRowUpdatedAfterPush].compactMap { $0 }.max()
        let rowCursor = newestRow.map { max($0, lastPulledAt ?? .distantPast) } ?? lastPulledAt
        return SyncCursor(rowUpdatedAt: rowCursor)
    }

    private static func pushDeletes(context: ModelContext, client: SupabaseClient, workspaceID: String) async throws {
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        guard !tombstones.isEmpty else { return }

        let remoteTombstones = tombstones.map { RemoteTombstone($0, workspaceID: workspaceID) }
        try await client
            .from("earnline_tombstones")
            .upsert(remoteTombstones)
            .execute()

        // One delete per entity table (`in (…)`) rather than one request per
        // tombstone — a large delete batch was otherwise N round-trips.
        let byEntity = Dictionary(grouping: tombstones, by: \.entity)
        for (entity, group) in byEntity {
            try await client
                .from(tableName(for: entity))
                .delete()
                .in("id", values: group.map { $0.recordID.uuidString })
                .eq("workspace_id", value: workspaceID)
                .execute()
            group.forEach(context.delete)
        }
    }

    private static func pushLocalRows(context: ModelContext,
                                      client: SupabaseClient,
                                      workspaceID: String) async throws {
        // Fetch only rows that can need a push — the steady state is zero,
        // and this runs on the main actor right after launch, where
        // materializing the whole Entry table stalled the UI on large
        // ledgers. `syncStateRaw == nil` is matched explicitly: `needsSync`
        // treats it as dirty, but in SQL `NULL != 'synced'` is not true.
        let synced = SyncState.synced.rawValue
        let clients = try context.fetch(FetchDescriptor<Client>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }))
        let headings = try context.fetch(FetchDescriptor<Heading>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }))
        let entries = try context.fetch(FetchDescriptor<Entry>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }))
        let projectIcons = try context.fetch(FetchDescriptor<ProjectIconPreference>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }))

        // Snapshot the dirty rows *and their edit stamps* before each upsert:
        // the UI stays live while the request is on the wire, so only the rows
        // (at the versions) that were actually pushed may be marked synced —
        // re-filtering after the await would swallow mid-flight edits, and the
        // next pull would then visibly revert them.
        let dirtyClients = clients.filter(\.needsSync)
        if !dirtyClients.isEmpty {
            let payload = dirtyClients.map { RemoteClient($0, workspaceID: workspaceID) }
            let stamps = dirtyClients.map(\.syncUpdatedAt)
            try await client.from("earnline_clients").upsert(payload).execute()
            markPushed(dirtyClients, stamps: stamps)
        }

        let dirtyHeadings = headings.filter(\.needsSync)
        if !dirtyHeadings.isEmpty {
            let payload = dirtyHeadings.map { RemoteHeading($0, workspaceID: workspaceID) }
            let stamps = dirtyHeadings.map(\.syncUpdatedAt)
            try await client.from("earnline_headings").upsert(payload).execute()
            markPushed(dirtyHeadings, stamps: stamps)
        }

        let dirtyProjectIcons = projectIcons.filter(\.needsSync)
        if !dirtyProjectIcons.isEmpty {
            let payload = dirtyProjectIcons.map { RemoteProjectIcon($0, workspaceID: workspaceID) }
            let stamps = dirtyProjectIcons.map(\.syncUpdatedAt)
            try await client.from("earnline_project_icons").upsert(payload).execute()
            markPushed(dirtyProjectIcons, stamps: stamps)
        }

        var dirtyEntries: [Entry] = []
        var entryPayload: [RemoteEntry] = []
        for entry in entries where entry.needsSync {
            guard let record = RemoteEntry(entry, workspaceID: workspaceID) else { continue }
            dirtyEntries.append(entry)
            entryPayload.append(record)
        }
        if !entryPayload.isEmpty {
            let stamps = dirtyEntries.map(\.syncUpdatedAt)
            try await client.from("earnline_entries").upsert(entryPayload).execute()
            markPushed(dirtyEntries, stamps: stamps)
        }
    }

    /// SQLite caps bound variables; batches past this size fall back to one
    /// full-table fetch, which is also the cheapest plan for a first pull
    /// into an empty or nearly-empty store.
    private static let idPredicateLimit = 300

    private static func localEntries(ids: [UUID], context: ModelContext) throws -> [Entry] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= idPredicateLimit else { return try context.fetch(FetchDescriptor<Entry>()) }
        return try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { ids.contains($0.id) }))
    }

    private static func localHeadings(ids: [UUID], context: ModelContext) throws -> [Heading] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= idPredicateLimit else { return try context.fetch(FetchDescriptor<Heading>()) }
        return try context.fetch(FetchDescriptor<Heading>(predicate: #Predicate { ids.contains($0.id) }))
    }

    private static func localClients(ids: [UUID], context: ModelContext) throws -> [Client] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= idPredicateLimit else { return try context.fetch(FetchDescriptor<Client>()) }
        return try context.fetch(FetchDescriptor<Client>(predicate: #Predicate { ids.contains($0.id) }))
    }

    private static func localProjectIcons(
        ids: [UUID],
        context: ModelContext
    ) throws -> [ProjectIconPreference] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= idPredicateLimit else {
            return try context.fetch(FetchDescriptor<ProjectIconPreference>())
        }
        return try context.fetch(FetchDescriptor<ProjectIconPreference>(
            predicate: #Predicate { ids.contains($0.id) }
        ))
    }

    /// Mark exactly the pushed rows synced — skipping any that were edited or
    /// deleted while the upsert was in flight, so they stay dirty for the next
    /// pass instead of being silently dropped. The post-push pull sets the
    /// server baseline; leaving it nil until then fails closed on a conflict.
    private static func markPushed<Model: SyncableModel>(_ models: [Model], stamps: [Date]) {
        for (model, stamp) in zip(models, stamps) where !model.isDeleted && model.syncUpdatedAt == stamp {
            model.syncState = .synced
            model.lastSyncedAt = nil
        }
    }

    @discardableResult
    private static func pullRemoteRows(context: ModelContext,
                                       client: SupabaseClient,
                                       workspaceID: String,
                                       lastPulledAt: Date?,
                                       conflictResolution: ConflictResolution) async throws -> Date? {
        // Clients stay a full fetch: there are few, and every remote entry
        // needs its owner resolvable even when that client wasn't in this
        // pull. Headings and entries are indexed only to merge the pulled
        // batch, so they're fetched by the batch's ids below — an incremental
        // pull touches a handful of rows, not the whole table.
        let localClients = try context.fetch(FetchDescriptor<Client>())

        let clientSince = localClients.isEmpty ? nil : lastPulledAt
        let headingSince = try context.fetchCount(FetchDescriptor<Heading>()) == 0 ? nil : lastPulledAt
        let entrySince = try context.fetchCount(FetchDescriptor<Entry>()) == 0 ? nil : lastPulledAt
        let projectIconSince = try context.fetchCount(FetchDescriptor<ProjectIconPreference>()) == 0
            ? nil
            : lastPulledAt

        let remoteClients = try await fetchClients(client: client, workspaceID: workspaceID, updatedAfter: clientSince)
        let remoteHeadings = try await fetchHeadings(client: client, workspaceID: workspaceID, updatedAfter: headingSince)
        let remoteEntries = try await fetchEntries(client: client, workspaceID: workspaceID, updatedAfter: entrySince)
        let remoteProjectIcons = try await fetchProjectIcons(
            client: client,
            workspaceID: workspaceID,
            updatedAfter: projectIconSince
        )

        let localHeadings = try localHeadings(ids: remoteHeadings.map(\.id), context: context)
        let localEntries = try localEntries(ids: remoteEntries.map(\.id), context: context)
        let localProjectIcons = try localProjectIcons(ids: remoteProjectIcons.map(\.id), context: context)

        let maxUpdatedAt = (remoteClients.compactMap { SyncDateCodec.parseTimestamp($0.updatedAt) }
            + remoteHeadings.compactMap { SyncDateCodec.parseTimestamp($0.updatedAt) }
            + remoteEntries.compactMap { SyncDateCodec.parseTimestamp($0.updatedAt) }
            + remoteProjectIcons.compactMap {
                ProjectIconResolver.normalizedKey(for: $0.projectKey).isEmpty
                    ? nil
                    : SyncDateCodec.parseTimestamp($0.updatedAt)
            }).max()

        var clientsByID = Dictionary(uniqueKeysWithValues: localClients.map { ($0.id, $0) })
        var conflictCount = 0

        // Rows whose dates can't be parsed are skipped, not defaulted: the old
        // "now"/"today" fallbacks silently rewrote timestamps and entry dates,
        // which corrupted conflict resolution and the visible ledger. A skipped
        // row is retried on the next pass (`gte` cursor is inclusive).
        for record in remoteClients {
            guard let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt) else { continue }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            if let local = clientsByID[record.id] {
                if conflictsWithDirtyLocal(remoteUpdatedAt: remoteUpdatedAt,
                                           localLastSyncedAt: local.lastSyncedAt,
                                           localState: local.syncState) {
                    if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    continue
                }
                guard shouldApplyRemote(localState: local.syncState) else { continue }
                local.name = record.name
                local.colorHex = record.colorHex
                local.sortIndex = record.sortIndex
                local.createdAt = createdAt
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: remoteUpdatedAt)
            } else {
                let newClient = Client(id: record.id,
                                       name: record.name,
                                       colorHex: record.colorHex,
                                       sortIndex: record.sortIndex,
                                       createdAt: createdAt,
                                       updatedAt: remoteUpdatedAt,
                                       syncState: .synced,
                                       lastSyncedAt: remoteUpdatedAt)
                context.insert(newClient)
                clientsByID[record.id] = newClient
            }
        }

        var projectIconsByID = Dictionary(uniqueKeysWithValues: localProjectIcons.map { ($0.id, $0) })

        for record in remoteProjectIcons {
            let projectKey = ProjectIconResolver.normalizedKey(for: record.projectKey)
            guard !projectKey.isEmpty,
                  let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt) else { continue }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            let symbol = ProjectSymbol.resolved(record.symbolName)
            if let local = projectIconsByID[record.id] {
                if conflictsWithDirtyLocal(remoteUpdatedAt: remoteUpdatedAt,
                                           localLastSyncedAt: local.lastSyncedAt,
                                           localState: local.syncState) {
                    if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    continue
                }
                guard shouldApplyRemote(localState: local.syncState) else { continue }
                local.projectKey = projectKey
                local.symbol = symbol
                local.createdAt = createdAt
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: remoteUpdatedAt)
            } else {
                let preference = ProjectIconPreference(
                    id: record.id,
                    projectKey: projectKey,
                    symbol: symbol,
                    createdAt: createdAt,
                    updatedAt: remoteUpdatedAt,
                    syncState: .synced,
                    lastSyncedAt: remoteUpdatedAt
                )
                context.insert(preference)
                projectIconsByID[record.id] = preference
            }
        }

        var headingsByID = Dictionary(uniqueKeysWithValues: localHeadings.map { ($0.id, $0) })

        for record in remoteHeadings {
            guard let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt),
                  let date = SyncDateCodec.parseDay(record.date) else { continue }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            if let local = headingsByID[record.id] {
                if conflictsWithDirtyLocal(remoteUpdatedAt: remoteUpdatedAt,
                                           localLastSyncedAt: local.lastSyncedAt,
                                           localState: local.syncState) {
                    if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    continue
                }
                guard shouldApplyRemote(localState: local.syncState) else { continue }
                local.title = record.title
                local.date = date
                local.sortIndex = record.sortIndex
                local.createdAt = createdAt
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: remoteUpdatedAt)
            } else {
                let heading = Heading(id: record.id,
                                      title: record.title,
                                      date: date,
                                      sortIndex: record.sortIndex,
                                      createdAt: createdAt,
                                      updatedAt: remoteUpdatedAt,
                                      syncState: .synced,
                                      lastSyncedAt: remoteUpdatedAt)
                context.insert(heading)
                headingsByID[record.id] = heading
            }
        }

        var entriesByID = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })

        for record in remoteEntries {
            guard let owner = clientsByID[record.clientID] else { continue }
            guard let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt),
                  let date = SyncDateCodec.parseDay(record.date) else { continue }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            // A malformed hold date drops just the hold, not the whole row.
            let holdUntil = record.holdUntil.flatMap(SyncDateCodec.parseDay)
            if let local = entriesByID[record.id] {
                if conflictsWithDirtyLocal(remoteUpdatedAt: remoteUpdatedAt,
                                           localLastSyncedAt: local.lastSyncedAt,
                                           localState: local.syncState) {
                    if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    continue
                }
                guard shouldApplyRemote(localState: local.syncState) else { continue }
                local.amount = record.amount.decimal
                local.currencyCode = record.currencyCode
                local.project = record.project
                local.task = record.task
                local.date = date
                local.holdUntil = holdUntil
                local.statusRaw = EntryStatus.fromSyncRawValue(record.status).rawValue
                local.sortIndex = record.sortIndex
                local.createdAt = createdAt
                local.updatedAt = remoteUpdatedAt
                local.client = owner
                local.markSynced(at: remoteUpdatedAt)
            } else {
                let entry = Entry(id: record.id,
                                  amount: record.amount.decimal,
                                  currencyCode: record.currencyCode,
                                  project: record.project,
                                  task: record.task,
                                  date: date,
                                  holdUntil: holdUntil,
                                  status: EntryStatus.fromSyncRawValue(record.status),
                                  sortIndex: record.sortIndex,
                                  createdAt: createdAt,
                                  updatedAt: remoteUpdatedAt,
                                  syncState: .synced,
                                  lastSyncedAt: remoteUpdatedAt)
                entry.client = owner
                context.insert(entry)
                entriesByID[record.id] = entry
            }
        }

        if conflictCount > 0 { throw SyncConflictError.detected(conflictCount) }
        return maxUpdatedAt
    }

    private static func applyRemoteTombstones(_ records: [RemoteTombstone],
                                              context: ModelContext,
                                              conflictResolution: ConflictResolution) throws {
        guard !records.isEmpty else { return }
        // Only rows named by a tombstone can be deleted, so index just those
        // instead of materializing three whole tables on every pass.
        func ids(_ entity: SyncEntity) -> [UUID] {
            records.filter { $0.entity == entity.rawValue }.map(\.recordID)
        }
        let clientsByID = Dictionary(uniqueKeysWithValues:
            try localClients(ids: ids(.client), context: context).map { ($0.id, $0) })
        let headingsByID = Dictionary(uniqueKeysWithValues:
            try localHeadings(ids: ids(.heading), context: context).map { ($0.id, $0) })
        let entriesByID = Dictionary(uniqueKeysWithValues:
            try localEntries(ids: ids(.entry), context: context).map { ($0.id, $0) })
        var conflictCount = 0
        for record in records {
            guard let entity = SyncEntity(rawValue: record.entity) else { continue }
            // A tombstone we can't date must not delete anything — the old
            // `Date()` fallback made every malformed tombstone look brand new,
            // which let it override any local edit.
            guard let deletedAt = SyncDateCodec.parseTimestamp(record.deletedAt) else { continue }
            switch entity {
            case .client:
                if let client = clientsByID[record.recordID] {
                    if conflictsWithDirtyLocal(remoteUpdatedAt: deletedAt,
                                               localLastSyncedAt: client.lastSyncedAt,
                                               localState: client.syncState) {
                        if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    } else if shouldApplyRemote(localState: client.syncState) {
                        context.delete(client)
                    }
                }
            case .heading:
                if let heading = headingsByID[record.recordID] {
                    if conflictsWithDirtyLocal(remoteUpdatedAt: deletedAt,
                                               localLastSyncedAt: heading.lastSyncedAt,
                                               localState: heading.syncState) {
                        if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    } else if shouldApplyRemote(localState: heading.syncState) {
                        context.delete(heading)
                    }
                }
            case .entry:
                if let entry = entriesByID[record.recordID] {
                    if conflictsWithDirtyLocal(remoteUpdatedAt: deletedAt,
                                               localLastSyncedAt: entry.lastSyncedAt,
                                               localState: entry.syncState) {
                        if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    } else if shouldApplyRemote(localState: entry.syncState) {
                        context.delete(entry)
                    }
                }
            }
        }
        if conflictCount > 0 { throw SyncConflictError.detected(conflictCount) }
    }

    /// A clean local row can take a remote copy. Dirty rows stay intact until
    /// their remote version is known to be unchanged, or the user explicitly
    /// chooses to keep this device's copy.
    static func shouldApplyRemote(localState: SyncState) -> Bool {
        localState == .synced
    }

    /// `lastSyncedAt` stores the latest server version actually observed for a
    /// row. Comparing that baseline with server `updated_at` avoids relying on
    /// device clocks, which are not a valid conflict-resolution source.
    static func conflictsWithDirtyLocal(remoteUpdatedAt: Date,
                                        localLastSyncedAt: Date?,
                                        localState: SyncState) -> Bool {
        guard localState != .synced else { return false }
        guard let localLastSyncedAt else { return true }
        return remoteUpdatedAt > localLastSyncedAt
    }

    /// Page through every matching row. PostgREST caps a response at the
    /// project's `db-max-rows` (1000 by default), so an unpaginated `select()`
    /// silently truncated large workspaces. Order by the cursor column then `id`
    /// for a stable total order across pages (unordered `.range()` could skip or
    /// repeat rows), and keep requesting until a short page comes back.
    private static func fetchPaged<T: Decodable>(_ type: T.Type,
                                                 client: SupabaseClient,
                                                 table: String,
                                                 workspaceID: String,
                                                 cursorColumn: String,
                                                 since: Date?) async throws -> [T] {
        var out: [T] = []
        var from = 0
        while true {
            var query = client
                .from(table)
                .select()
                .eq("workspace_id", value: workspaceID)
            if let since {
                query = query.gte(cursorColumn, value: SyncDateCodec.timestampString(since))
            }
            let page: [T] = try await query
                .order(cursorColumn, ascending: true)
                .order("id", ascending: true)
                .range(from: from, to: from + pageSize - 1)
                .execute()
                .value
            out.append(contentsOf: page)
            if page.count < pageSize { break }
            from += pageSize
        }
        return out
    }

    private static func fetchClients(client: SupabaseClient,
                                     workspaceID: String,
                                     updatedAfter: Date?) async throws -> [RemoteClient] {
        try await fetchPaged(RemoteClient.self, client: client, table: "earnline_clients",
                             workspaceID: workspaceID, cursorColumn: "updated_at", since: updatedAfter)
    }

    private static func fetchHeadings(client: SupabaseClient,
                                      workspaceID: String,
                                      updatedAfter: Date?) async throws -> [RemoteHeading] {
        try await fetchPaged(RemoteHeading.self, client: client, table: "earnline_headings",
                             workspaceID: workspaceID, cursorColumn: "updated_at", since: updatedAfter)
    }

    private static func fetchEntries(client: SupabaseClient,
                                     workspaceID: String,
                                     updatedAfter: Date?) async throws -> [RemoteEntry] {
        try await fetchPaged(RemoteEntry.self, client: client, table: "earnline_entries",
                             workspaceID: workspaceID, cursorColumn: "updated_at", since: updatedAfter)
    }

    private static func fetchProjectIcons(
        client: SupabaseClient,
        workspaceID: String,
        updatedAfter: Date?
    ) async throws -> [RemoteProjectIcon] {
        try await fetchPaged(
            RemoteProjectIcon.self,
            client: client,
            table: "earnline_project_icons",
            workspaceID: workspaceID,
            cursorColumn: "updated_at",
            since: updatedAfter
        )
    }

    private static func fetchTombstones(client: SupabaseClient,
                                        workspaceID: String,
                                        deletedAfter: Date?) async throws -> [RemoteTombstone] {
        try await fetchPaged(RemoteTombstone.self, client: client, table: "earnline_tombstones",
                             workspaceID: workspaceID, cursorColumn: "deleted_at", since: deletedAfter)
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
