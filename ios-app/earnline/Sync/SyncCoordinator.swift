import Foundation
import SwiftData
import Supabase

@MainActor
enum SyncCoordinator {
    // The Edge proxy accepts up to 1,000 rows, but 250 keeps actual upserts
    // comfortably below its body/connection limits on a constrained network.
    private static let pageSize = 250

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
                // swiftlint:disable:next line_length
                return String(localized: "Cloud and iPhone changes conflict. Pending changes: \(count). Choose which copy to keep in Settings → Sync.")
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
    /// tuple is pushed only if the remote row still matches the last profile
    /// observed by this device; otherwise the existing conflict UI gets to
    /// decide which copy should win. When the row does not exist yet, the
    /// current device seeds it.
    static func syncWorkspaceProfile(client: SupabaseClient,
                                     workspaceID: String,
                                     local: WorkspaceProfilePayload,
                                     pushLocal: Bool,
                                     expectedRemoteUpdatedAt: Date? = nil,
                                     conflictResolution: ConflictResolution = .requireUserChoice) async throws -> RemoteWorkspaceProfile {
        let remote: [RemoteWorkspaceProfile] = try await client
            .from("earnline_profiles")
            .select()
            .eq("workspace_id", value: workspaceID)
            .limit(1)
            .execute()
            .value

        if let existing = remote.first {
            guard let remoteUpdatedAt = SyncDateCodec.parseTimestamp(existing.updatedAt) else {
                throw SyncError.invalidRemoteProfile
            }

            if !pushLocal {
                return existing
            }

            let baselineMatches = expectedRemoteUpdatedAt.map { $0 == remoteUpdatedAt } ?? false
            guard conflictResolution == .preferLocal || baselineMatches else {
                // A pending local profile edit without a matching baseline
                // cannot safely prove that the remote value is still the one
                // the user saw.
                throw SyncConflictError.detected(1)
            }
        }

        let response = try await versionedUpsert(
            client: client, table: "earnline_profiles", workspaceID: workspaceID,
            rows: [local], baselines: [expectedRemoteUpdatedAt],
            conflictResolution: conflictResolution
        )
        let profiles = try JSONDecoder().decode([RemoteWorkspaceProfile].self, from: response)
        guard let updated = profiles.first else { throw SyncError.invalidRemoteProfile }

        guard SyncDateCodec.parseTimestamp(updated.updatedAt) != nil else {
            throw SyncError.invalidRemoteProfile
        }
        return updated
    }

    /// Runs a full sync pass and returns the server-managed row cursor.
    /// Tombstones are paged and reapplied on every pass so a skewed device clock
    /// can never hide a remote deletion. `gte` makes row cursor boundaries
    /// idempotent to reapply.
    static func sync(context: ModelContext,
                     client: SupabaseClient,
                     workspaceID: String,
                     lastPulledAt: Date? = nil,
                     conflictResolution: ConflictResolution = .requireUserChoice,
                     usesBatchReads: Bool = false) async throws -> SyncCursor {
        try Task.checkCancellation()
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
        // Tombstones are append-only and replayed in full, so a row that was
        // deleted and later restored is still named by a live tombstone. Both
        // the delete decision above and the pull below compare against the
        // newest `deleted_at` per record rather than deleting on sight.
        let deletionTimes = latestDeletionTimes(remoteTombstones)

        // Pull before normal row pushes. A previous version pushed first, which
        // made the local device that happened to reconnect last overwrite a
        // remote edit before conflict detection ever ran.
        let maxRowUpdatedAt = try await pullRemoteRows(context: context,
                                                       client: client,
                                                       workspaceID: workspaceID,
                                                       lastPulledAt: lastPulledAt,
                                                       deletionTimes: deletionTimes,
                                                       conflictResolution: conflictResolution,
                                                       usesBatchReads: usesBatchReads)
        // Materialize remote cascade deletes before pushing rows so an entry
        // whose client vanished remotely cannot violate the remote FK.
        try context.save()

        try await pushLocalRows(context: context,
                                client: client,
                                workspaceID: workspaceID,
                                conflictResolution: conflictResolution)

        // Read the server-written `updated_at` values for rows just pushed.
        // A device clock is not a valid conflict baseline: if this refresh is
        // interrupted, the row deliberately keeps a nil baseline and a later
        // concurrent edit requires a user choice instead of being overwritten.
        //
        // Start from what the first pull already observed: everything older was
        // just merged, so re-reading it would double every pass's transfer and
        // merge cost for rows this push cannot have changed.
        let pushCursor = [maxRowUpdatedAt, lastPulledAt].compactMap { $0 }.max()
        let maxRowUpdatedAfterPush = try await pullRemoteRows(context: context,
                                                              client: client,
                                                              workspaceID: workspaceID,
                                                              lastPulledAt: pushCursor,
                                                              deletionTimes: deletionTimes,
                                                              conflictResolution: conflictResolution,
                                                              usesBatchReads: usesBatchReads)

        try context.save()

        let newestRow = [maxRowUpdatedAt, maxRowUpdatedAfterPush].compactMap { $0 }.max()
        let rowCursor = newestRow.map { max($0, lastPulledAt ?? .distantPast) } ?? lastPulledAt
        return SyncCursor(rowUpdatedAt: rowCursor)
    }

    /// `in (…)` filters travel in the URL, and a UUID costs ~37 characters
    /// there, so a few hundred ids already approach the 8 KB request line that
    /// PostgREST sits behind. Deleting a client with its entries used to build
    /// one unbounded URL: the server answered 414, the retry ladder rebuilt the
    /// identical request, and sync stayed wedged until a local reset.
    private static let deleteBatchSize = 100

    private static func pushDeletes(context: ModelContext, client: SupabaseClient, workspaceID: String) async throws {
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        guard !tombstones.isEmpty else { return }

        // The proxy transport rejects row batches over `pageSize`, so match it
        // here rather than discovering the cap as an opaque 400 mid-pass.
        for chunk in tombstones.chunked(into: pageSize) {
            try await client
                .from("earnline_tombstones")
                // Retry must preserve the original server timestamp. The
                // database owns `deleted_at`; duplicate ids are a no-op.
                .upsert(chunk.map { RemoteTombstone($0, workspaceID: workspaceID) },
                        onConflict: "id",
                        ignoreDuplicates: true)
                .execute()
        }

        // One delete per entity table (`in (…)`) rather than one request per
        // tombstone — a large delete batch was otherwise N round-trips — but
        // chunked, so the URL stays bounded however many rows went at once.
        // Local tombstones are cleared per chunk: a failure partway through
        // leaves the undelivered ones queued for the next pass.
        let byEntity = Dictionary(grouping: tombstones, by: \.entity)
        for (entity, group) in byEntity {
            for chunk in group.chunked(into: deleteBatchSize) {
                try await client
                    .from(tableName(for: entity))
                    .delete()
                    .in("id", values: chunk.map { $0.recordID.uuidString })
                    .eq("workspace_id", value: workspaceID)
                    .execute()
                chunk.forEach(context.delete)
            }
        }
    }

    private static func pushLocalRows(context: ModelContext,
                                      client: SupabaseClient,
                                      workspaceID: String,
                                      conflictResolution: ConflictResolution) async throws {
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
        let monthReviews = try context.fetch(FetchDescriptor<MonthReview>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }))

        // Snapshot the dirty rows *and their edit stamps* before each upsert:
        // the UI stays live while the request is on the wire, so only the rows
        // (at the versions) that were actually pushed may be marked synced —
        // re-filtering after the await would swallow mid-flight edits, and the
        // next pull would then visibly revert them.
        let dirtyClients = clients.filter(\.needsSync)
        for candidates in dirtyClients.chunked(into: pageSize) {
            let chunk = candidates.filter { !$0.isDeleted && $0.modelContext != nil && $0.needsSync }
            guard !chunk.isEmpty else { continue }
            let payload = chunk.map { RemoteClient($0, workspaceID: workspaceID) }
            let stamps = chunk.map(\.syncUpdatedAt)
            let response = try await versionedUpsert(
                client: client, table: "earnline_clients", workspaceID: workspaceID,
                rows: payload, baselines: chunk.map(\.lastSyncedAt), conflictResolution: conflictResolution
            )
            try markPushed(chunk, stamps: stamps, response: response)
        }

        let dirtyHeadings = headings.filter(\.needsSync)
        for candidates in dirtyHeadings.chunked(into: pageSize) {
            let chunk = candidates.filter { !$0.isDeleted && $0.modelContext != nil && $0.needsSync }
            guard !chunk.isEmpty else { continue }
            let payload = chunk.map { RemoteHeading($0, workspaceID: workspaceID) }
            let stamps = chunk.map(\.syncUpdatedAt)
            let response = try await versionedUpsert(
                client: client, table: "earnline_headings", workspaceID: workspaceID,
                rows: payload, baselines: chunk.map(\.lastSyncedAt), conflictResolution: conflictResolution
            )
            try markPushed(chunk, stamps: stamps, response: response)
        }

        let dirtyProjectIcons = projectIcons.filter(\.needsSync)
        for candidates in dirtyProjectIcons.chunked(into: pageSize) {
            let chunk = candidates.filter { !$0.isDeleted && $0.modelContext != nil && $0.needsSync }
            guard !chunk.isEmpty else { continue }
            let payload = chunk.map { RemoteProjectIcon($0, workspaceID: workspaceID) }
            let stamps = chunk.map(\.syncUpdatedAt)
            let response = try await versionedUpsert(
                client: client, table: "earnline_project_icons", workspaceID: workspaceID,
                rows: payload, baselines: chunk.map(\.lastSyncedAt), conflictResolution: conflictResolution
            )
            try markPushed(chunk, stamps: stamps, response: response)
        }

        let dirtyMonthReviews = monthReviews.filter(\.needsSync)
        for candidates in dirtyMonthReviews.chunked(into: pageSize) {
            let chunk = candidates.filter { !$0.isDeleted && $0.modelContext != nil && $0.needsSync }
            guard !chunk.isEmpty else { continue }
            let payload = chunk.map { RemoteMonthReview($0, workspaceID: workspaceID) }
            let stamps = chunk.map(\.syncUpdatedAt)
            let response = try await versionedUpsert(
                client: client, table: "earnline_month_reviews", workspaceID: workspaceID,
                rows: payload, baselines: chunk.map(\.lastSyncedAt), conflictResolution: conflictResolution
            )
            try markPushed(chunk, stamps: stamps, response: response)
        }

        for candidates in entries.chunked(into: pageSize) {
            var rows: [Entry] = []
            var payload: [RemoteEntry] = []
            var stamps: [Date] = []
            for entry in candidates where !entry.isDeleted && entry.modelContext != nil && entry.needsSync {
                guard let record = RemoteEntry(entry, workspaceID: workspaceID) else { continue }
                rows.append(entry)
                payload.append(record)
                stamps.append(entry.syncUpdatedAt)
            }
            guard !rows.isEmpty else { continue }
            let response = try await versionedUpsert(
                client: client, table: "earnline_entries", workspaceID: workspaceID,
                rows: payload, baselines: rows.map(\.lastSyncedAt), conflictResolution: conflictResolution
            )
            try markPushed(rows, stamps: stamps, response: response)
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

    private static func localMonthReviews(
        ids: [UUID],
        context: ModelContext
    ) throws -> [MonthReview] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= idPredicateLimit else {
            return try context.fetch(FetchDescriptor<MonthReview>())
        }
        return try context.fetch(FetchDescriptor<MonthReview>(
            predicate: #Predicate { ids.contains($0.id) }
        ))
    }

    /// Mark exactly the pushed rows synced — skipping any that were edited or
    /// deleted while the upsert was in flight, so they stay dirty for the next
    /// pass instead of being silently dropped. The post-push pull sets the
    /// server baseline; leaving it nil until then fails closed on a conflict.
    private struct WriteParameters<Row: Encodable>: Encodable {
        let table: String
        let workspaceID: String
        let rows: [Row]
        let expectedVersions: [Int64?]
        let force: Bool

        enum CodingKeys: String, CodingKey {
            case table = "p_table"
            case workspaceID = "p_workspace_id"
            case rows = "p_rows"
            case expectedVersions = "p_expected_versions"
            case force = "p_force"
        }
    }

    private static func versionedUpsert<Row: Encodable>(
        client: SupabaseClient, table: String, workspaceID: String,
        rows: [Row], baselines: [Date?], conflictResolution: ConflictResolution
    ) async throws -> Data {
        do {
            return try await client.rpc("earnline_upsert_versioned", params: WriteParameters(
                table: table, workspaceID: workspaceID, rows: rows,
                expectedVersions: baselines.map { $0.map(SyncDateCodec.versionMicroseconds) },
                force: conflictResolution == .preferLocal
            )).execute().data
        } catch let error as PostgrestError where error.code == "PT409" {
            throw SyncConflictError.detected(1)
        }
    }

    private struct WriteAcknowledgment: Decodable {
        let id: UUID
        let updatedAt: String
        enum CodingKeys: String, CodingKey {
            case id
            case updatedAt = "updated_at"
        }
    }

    private static func markPushed<Model: SyncableModel>(
        _ models: [Model], stamps: [Date], response: Data
    ) throws {
        let records = try JSONDecoder().decode([WriteAcknowledgment].self, from: response)
        guard records.count == models.count, zip(records, models).allSatisfy({ $0.id == $1.id }) else {
            throw SyncError.invalidRemoteCursor(table: "write")
        }
        let versions = try records.map { record -> Date in
            guard let version = SyncDateCodec.parseTimestamp(record.updatedAt) else {
                throw SyncError.invalidRemoteCursor(table: "write")
            }
            return version
        }
        for (index, model) in models.enumerated() where !model.isDeleted && model.modelContext != nil {
            // The response is ordered by the RPC. Keep a later local edit dirty,
            // but acknowledge its own earlier write as the new cloud baseline.
            if model.syncUpdatedAt == stamps[index] {
                model.markSynced(at: versions[index])
            } else {
                model.lastSyncedAt = versions[index]
            }
        }
    }

    @discardableResult
    // This remains the ordered merge boundary for five remote models. The
    // entity helpers below preserve each model's validation and conflict rules.
    // swiftlint:disable:next function_body_length
    private static func pullRemoteRows(context: ModelContext,
                                       client: SupabaseClient,
                                       workspaceID: String,
                                       lastPulledAt: Date?,
                                       deletionTimes: [DeletionKey: Date],
                                       conflictResolution: ConflictResolution,
                                       usesBatchReads: Bool) async throws -> Date? {
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
        let monthReviewSince = try context.fetchCount(FetchDescriptor<MonthReview>()) == 0
            ? nil
            : lastPulledAt

        let batch = usesBatchReads ? try await SyncBatchReader.read(client: client, workspace: workspaceID, since: [
            "earnline_clients": clientSince, "earnline_headings": headingSince, "earnline_entries": entrySince,
            "earnline_project_icons": projectIconSince, "earnline_month_reviews": monthReviewSince,
        ]) : nil
        let remoteClients: [RemoteClient]
        let remoteHeadings: [RemoteHeading]
        let remoteEntries: [RemoteEntry]
        let remoteProjectIcons: [RemoteProjectIcon]
        let remoteMonthReviews: [RemoteMonthReview]
        if let batch {
            remoteClients = batch.clients
            remoteHeadings = batch.headings
            remoteEntries = batch.entries
            remoteProjectIcons = batch.projectIcons
            remoteMonthReviews = batch.monthReviews
        } else {
            remoteClients = try await fetchClients(client: client, workspaceID: workspaceID, updatedAfter: clientSince)
            remoteHeadings = try await fetchHeadings(client: client, workspaceID: workspaceID, updatedAfter: headingSince)
            remoteEntries = try await fetchEntries(client: client, workspaceID: workspaceID, updatedAfter: entrySince)
            remoteProjectIcons = try await fetchProjectIcons(client: client, workspaceID: workspaceID, updatedAfter: projectIconSince)
            remoteMonthReviews = try await fetchMonthReviews(client: client, workspaceID: workspaceID, updatedAfter: monthReviewSince)
        }

        // A retained tombstone stays authoritative until the row is explicitly
        // restored with a *newer* server timestamp. Without this the pass would
        // re-insert every row the tombstone loop just deleted, and the next pass
        // would delete it again — a row visibly flapping on every sync.
        let applicableClients = remoteClients.filter {
            appliesOverTombstone($0.updatedAt, .client, $0.id, deletionTimes)
        }
        let applicableHeadings = remoteHeadings.filter {
            appliesOverTombstone($0.updatedAt, .heading, $0.id, deletionTimes)
        }
        let applicableEntries = remoteEntries.filter {
            appliesOverTombstone($0.updatedAt, .entry, $0.id, deletionTimes)
        }

        let localHeadings = try localHeadings(ids: applicableHeadings.map(\.id), context: context)
        let localEntries = try localEntries(ids: applicableEntries.map(\.id), context: context)
        // Icons are unique on project key as well as id. An incremental id
        // fetch would miss a local row that already owns the incoming key
        // under a different id, and inserting then fails the unique save.
        let localProjectIcons = try context.fetch(FetchDescriptor<ProjectIconPreference>())
        let localMonthReviewRows = try localMonthReviews(
            ids: remoteMonthReviews.map(\.id),
            context: context
        )

        let maxUpdatedAt = (remoteClients.compactMap { record in
                SyncValidation.isValidClient(name: record.name, colorHex: record.colorHex)
                    ? SyncDateCodec.parseTimestamp(record.updatedAt)
                    : nil
        }
            + remoteHeadings.compactMap { record in
                SyncValidation.isValidHeading(title: record.title)
                    ? SyncDateCodec.parseTimestamp(record.updatedAt)
                    : nil
            }
            + remoteEntries.compactMap { record in
                SyncValidation.isValidEntry(amount: record.amount.decimal,
                                            currencyCode: record.currencyCode,
                                            project: record.project,
                                            task: record.task,
                                            status: record.status)
                    ? SyncDateCodec.parseTimestamp(record.updatedAt)
                    : nil
            }
            + remoteProjectIcons.compactMap {
                ProjectIconResolver.normalizedKey(for: $0.projectKey).isEmpty
                    || $0.projectKey.unicodeScalars.count > Limits.maxProjectLength
                    || $0.projectKey != ProjectIconResolver.normalizedKey(for: $0.projectKey)
                    || ProjectSymbol(rawValue: $0.symbolName) == nil
                    ? nil
                    : SyncDateCodec.parseTimestamp($0.updatedAt)
            }
            + remoteMonthReviews.compactMap { record in
                let closedAtIsValid = record.closedAt == nil
                    || record.closedAt.flatMap(SyncDateCodec.parseTimestamp) != nil
                guard MonthReview.isValid(note: record.note),
                      let monthStart = SyncDateCodec.parseDay(record.monthStart),
                      SyncDateCodec.dayString(monthStart).hasSuffix("-01"),
                      record.id == MonthReview.id(for: monthStart),
                      closedAtIsValid
                else { return nil }
                return SyncDateCodec.parseTimestamp(record.updatedAt)
            }).max()

        var clientsByID = Dictionary(uniqueKeysWithValues: localClients.map { ($0.id, $0) })
        var projectIconsByID = Dictionary(uniqueKeysWithValues: localProjectIcons.map { ($0.id, $0) })
        var monthReviewsByID = Dictionary(uniqueKeysWithValues: localMonthReviewRows.map { ($0.id, $0) })
        var headingsByID = Dictionary(uniqueKeysWithValues: localHeadings.map { ($0.id, $0) })
        var entriesByID = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })

        // Keep the merge order explicit: entries depend on clients, and each
        // helper preserves the validation and conflict policy of its model.
        var conflictCount = mergeClients(
            applicableClients,
            context: context,
            clientsByID: &clientsByID,
            conflictResolution: conflictResolution
        )
        conflictCount += mergeProjectIcons(
            remoteProjectIcons,
            context: context,
            projectIconsByID: &projectIconsByID,
            conflictResolution: conflictResolution
        )
        conflictCount += mergeMonthReviews(
            remoteMonthReviews,
            context: context,
            monthReviewsByID: &monthReviewsByID,
            conflictResolution: conflictResolution
        )
        conflictCount += mergeHeadings(
            applicableHeadings,
            context: context,
            headingsByID: &headingsByID,
            conflictResolution: conflictResolution
        )
        conflictCount += mergeEntries(
            applicableEntries,
            context: context,
            clientsByID: clientsByID,
            entriesByID: &entriesByID,
            conflictResolution: conflictResolution
        )

        if conflictCount > 0 { throw SyncConflictError.detected(conflictCount) }
        return maxUpdatedAt
    }

    // Rows whose dates can't be parsed are skipped, not defaulted: the old
    // "now"/"today" fallbacks silently rewrote timestamps and entry dates,
    // which corrupted conflict resolution and the visible ledger. A skipped
    // row is retried on the next pass (`gte` cursor is inclusive).
    private static func mergeClients(
        _ records: [RemoteClient],
        context: ModelContext,
        clientsByID: inout [UUID: Client],
        conflictResolution: ConflictResolution
    ) -> Int {
        var conflictCount = 0
        for record in records {
            guard SyncValidation.isValidClient(name: record.name, colorHex: record.colorHex),
                  let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt) else { continue }
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
        return conflictCount
    }

    private static func mergeProjectIcons(
        _ records: [RemoteProjectIcon],
        context: ModelContext,
        projectIconsByID: inout [UUID: ProjectIconPreference],
        conflictResolution: ConflictResolution
    ) -> Int {
        var conflictCount = 0
        var projectIconsByKey: [String: ProjectIconPreference] = [:]
        for icon in projectIconsByID.values {
            projectIconsByKey[icon.projectKey] = icon
        }
        for record in records {
            let projectKey = ProjectIconResolver.normalizedKey(for: record.projectKey)
            guard !projectKey.isEmpty,
                  projectKey.unicodeScalars.count <= Limits.maxProjectLength,
                  projectKey == record.projectKey,
                  let symbol = ProjectSymbol(rawValue: record.symbolName),
                  let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt) else { continue }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            // Icons are unique on both id and project key. A remote row that
            // reused the key under a different id must update the local row,
            // not insert a duplicate that then fails the whole sync save.
            if let local = projectIconsByID[record.id] ?? projectIconsByKey[projectKey] {
                if conflictsWithDirtyLocal(remoteUpdatedAt: remoteUpdatedAt,
                                           localLastSyncedAt: local.lastSyncedAt,
                                           localState: local.syncState) {
                    if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    continue
                }
                guard shouldApplyRemote(localState: local.syncState) else { continue }
                let previousKey = local.projectKey
                local.projectKey = projectKey
                local.symbol = symbol
                local.createdAt = createdAt
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: remoteUpdatedAt)
                if previousKey != projectKey {
                    projectIconsByKey.removeValue(forKey: previousKey)
                }
                projectIconsByKey[projectKey] = local
                projectIconsByID[local.id] = local
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
                projectIconsByKey[projectKey] = preference
            }
        }
        return conflictCount
    }

    private static func mergeMonthReviews(
        _ records: [RemoteMonthReview],
        context: ModelContext,
        monthReviewsByID: inout [UUID: MonthReview],
        conflictResolution: ConflictResolution
    ) -> Int {
        var conflictCount = 0
        for record in records {
            guard MonthReview.isValid(note: record.note),
                  let monthStart = SyncDateCodec.parseDay(record.monthStart),
                  SyncDateCodec.dayString(monthStart).hasSuffix("-01"),
                  record.id == MonthReview.id(for: monthStart),
                  let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt) else { continue }
            let closedAt: Date?
            if let closedAtRaw = record.closedAt {
                guard let parsedClosedAt = SyncDateCodec.parseTimestamp(closedAtRaw) else { continue }
                closedAt = parsedClosedAt
            } else {
                closedAt = nil
            }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            if let local = monthReviewsByID[record.id] {
                if conflictsWithDirtyLocal(remoteUpdatedAt: remoteUpdatedAt,
                                           localLastSyncedAt: local.lastSyncedAt,
                                           localState: local.syncState) {
                    if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    continue
                }
                guard shouldApplyRemote(localState: local.syncState) else { continue }
                local.monthStart = MonthReview.monthStart(of: monthStart)
                local.note = record.note
                local.closedAt = closedAt
                local.createdAt = createdAt
                local.updatedAt = remoteUpdatedAt
                local.markSynced(at: remoteUpdatedAt)
            } else {
                let review = MonthReview(
                    id: record.id,
                    monthStart: monthStart,
                    note: record.note,
                    closedAt: closedAt,
                    createdAt: createdAt,
                    updatedAt: remoteUpdatedAt,
                    syncState: .synced,
                    lastSyncedAt: remoteUpdatedAt
                )
                context.insert(review)
                monthReviewsByID[record.id] = review
            }
        }
        return conflictCount
    }

    private static func mergeHeadings(
        _ records: [RemoteHeading],
        context: ModelContext,
        headingsByID: inout [UUID: Heading],
        conflictResolution: ConflictResolution
    ) -> Int {
        var conflictCount = 0
        for record in records {
            guard SyncValidation.isValidHeading(title: record.title),
                  let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt),
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
        return conflictCount
    }

    private static func mergeEntries(
        _ records: [RemoteEntry],
        context: ModelContext,
        clientsByID: [UUID: Client],
        entriesByID: inout [UUID: Entry],
        conflictResolution: ConflictResolution
    ) -> Int {
        var conflictCount = 0
        for record in records {
            guard let owner = clientsByID[record.clientID] else { continue }
            guard SyncValidation.isValidEntry(amount: record.amount.decimal,
                                              currencyCode: record.currencyCode,
                                              project: record.project,
                                              task: record.task,
                                              status: record.status),
                  let remoteUpdatedAt = SyncDateCodec.parseTimestamp(record.updatedAt),
                  let date = SyncDateCodec.parseDay(record.date) else { continue }
            let createdAt = SyncDateCodec.parseTimestamp(record.createdAt) ?? remoteUpdatedAt
            let holdUntil = record.holdUntil.flatMap(SyncDateCodec.parseDay)
            guard record.holdUntil == nil || holdUntil != nil else { continue }
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
        return conflictCount
    }

    // Every entity has an explicit delete path so a malformed tombstone cannot
    // accidentally fall through to another model.
    // swiftlint:disable:next cyclomatic_complexity
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
                    } else if tombstoneApplies(deletedAt: deletedAt,
                                               localLastSyncedAt: client.lastSyncedAt,
                                               localSyncUpdatedAt: client.syncUpdatedAt,
                                               localState: client.syncState) {
                        context.delete(client)
                    }
                }
            case .heading:
                if let heading = headingsByID[record.recordID] {
                    if conflictsWithDirtyLocal(remoteUpdatedAt: deletedAt,
                                               localLastSyncedAt: heading.lastSyncedAt,
                                               localState: heading.syncState) {
                        if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    } else if tombstoneApplies(deletedAt: deletedAt,
                                               localLastSyncedAt: heading.lastSyncedAt,
                                               localSyncUpdatedAt: heading.syncUpdatedAt,
                                               localState: heading.syncState) {
                        context.delete(heading)
                    }
                }
            case .entry:
                if let entry = entriesByID[record.recordID] {
                    if conflictsWithDirtyLocal(remoteUpdatedAt: deletedAt,
                                               localLastSyncedAt: entry.lastSyncedAt,
                                               localState: entry.syncState) {
                        if conflictResolution == .requireUserChoice { conflictCount += 1 }
                    } else if tombstoneApplies(deletedAt: deletedAt,
                                               localLastSyncedAt: entry.lastSyncedAt,
                                               localSyncUpdatedAt: entry.syncUpdatedAt,
                                               localState: entry.syncState) {
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

    /// Identifies one deleted row across the tombstone entities.
    struct DeletionKey: Hashable {
        let entity: SyncEntity
        let recordID: UUID
    }

    /// Newest `deleted_at` per record. Tombstones are append-only and replayed
    /// in full on every pass, so the same row can carry several; only the latest
    /// deletion can still be authoritative over a restore.
    static func latestDeletionTimes(_ records: [RemoteTombstone]) -> [DeletionKey: Date] {
        var output: [DeletionKey: Date] = [:]
        for record in records {
            guard let entity = SyncEntity(rawValue: record.entity),
                  let deletedAt = SyncDateCodec.parseTimestamp(record.deletedAt) else { continue }
            let key = DeletionKey(entity: entity, recordID: record.recordID)
            output[key] = output[key].map { Swift.max($0, deletedAt) } ?? deletedAt
        }
        return output
    }

    /// Whether a remote tombstone still describes the local row, or has been
    /// superseded by a restore.
    ///
    /// A dirty local row is never deleted here — `conflictsWithDirtyLocal` has
    /// already routed it to a user choice, and `.preferLocal` deliberately keeps
    /// this device's copy. For a clean row the tombstone only wins when it is at
    /// least as new as the server version this device last observed: a row that
    /// was deleted, restored, and re-pushed carries a `lastSyncedAt` *after* the
    /// deletion, and must survive. Without this comparison the restored row was
    /// deleted again on the pass after the user chose to keep it, while the row
    /// still existed remotely.
    ///
    /// `localSyncUpdatedAt` is only the fallback for a row that has never
    /// completed a pull (nil baseline), matching the web client's rule.
    static func tombstoneApplies(deletedAt: Date,
                                 localLastSyncedAt: Date?,
                                 localSyncUpdatedAt: Date,
                                 localState: SyncState) -> Bool {
        guard localState == .synced else { return false }
        return deletedAt >= (localLastSyncedAt ?? localSyncUpdatedAt)
    }

    /// Whether a pulled row may be applied over the newest tombstone naming it.
    /// A row that is not strictly newer than its deletion is skipped, so the
    /// pull cannot re-insert what the tombstone loop just deleted.
    private static func appliesOverTombstone(_ updatedAt: String,
                                             _ entity: SyncEntity,
                                             _ recordID: UUID,
                                             _ deletionTimes: [DeletionKey: Date]) -> Bool {
        guard let deletedAt = deletionTimes[DeletionKey(entity: entity, recordID: recordID)] else { return true }
        guard let rowUpdatedAt = SyncDateCodec.parseTimestamp(updatedAt) else { return false }
        return rowUpdatedAt > deletedAt
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

    /// Page through every matching row with a descending `(server timestamp,
    /// id)` keyset. Offset ranges can skip rows when a concurrent upsert moves
    /// an earlier row across the next offset. The first page establishes the
    /// high-water mark; every later request asks strictly below its last row,
    /// so concurrent newer writes are left for the next inclusive sync pass.
    private static func fetchPaged<T: SyncCursorRecord>(
        _ type: T.Type,
        client: SupabaseClient,
        table: String,
        workspaceID: String,
        cursorColumn: String,
        since: Date?
    ) async throws -> [T] {
        var out: [T] = []
        var cursor: (timestamp: String, id: UUID)?
        while true {
            try Task.checkCancellation()
            var query = client
                .from(table)
                .select()
                .eq("workspace_id", value: workspaceID)
            if let since {
                query = query.gte(cursorColumn, value: SyncDateCodec.timestampString(since))
            }
            if let cursor {
                query = query.or(
                    "\(cursorColumn).lt.\(cursor.timestamp),and(\(cursorColumn).eq.\(cursor.timestamp),id.lt.\(cursor.id.uuidString))"
                )
            }
            let page: [T] = try await query
                .order(cursorColumn, ascending: false)
                .order("id", ascending: false)
                .range(from: 0, to: pageSize - 1)
                .execute()
                .value
            out.append(contentsOf: page)
            if page.count < pageSize { break }
            guard let last = page.last,
                  SyncDateCodec.parseTimestamp(last.syncCursorTimestamp) != nil else {
                throw SyncError.invalidRemoteCursor(table: table)
            }
            let next = (timestamp: last.syncCursorTimestamp, id: last.id)
            guard cursor?.timestamp != next.timestamp || cursor?.id != next.id else {
                throw SyncError.invalidRemoteCursor(table: table)
            }
            cursor = next
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

    private static func fetchMonthReviews(
        client: SupabaseClient,
        workspaceID: String,
        updatedAfter: Date?
    ) async throws -> [RemoteMonthReview] {
        try await fetchPaged(
            RemoteMonthReview.self,
            client: client,
            table: "earnline_month_reviews",
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

extension Array {
    /// Split into fixed-size batches, preserving order. Used to bound both the
    /// row count of an upsert body and the URL length of an `in (…)` delete —
    /// see `SyncCoordinator.deleteBatchSize`.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, count > size else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
