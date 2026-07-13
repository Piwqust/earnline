import Foundation
import SwiftUI
import SwiftData
import Supabase
import Network

/// Supabase sync orchestration split out of `AppModel`, together with the local
/// save/delete path that feeds it: the push/pull pass and its debounce, conflict
/// handoff, the retry backoff ladder, connectivity-driven reconnect, and the
/// realtime subscription. `AppModel` owns the state these mutate (`isSyncing`,
/// `syncMessage`, cursors, task handles); this extension keeps the orchestration
/// in one cohesive place instead of the main file.
extension AppModel {
    // MARK: Supabase

    var isSupabaseConfigured: Bool {
        let urlText = supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText),
              url.scheme?.lowercased() == "https",
              url.host() != nil else { return false }
        return !supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshSupabaseSession() async {
        guard isSupabaseConfigured else {
            syncMessage = String(localized: "Offline")
            return
        }
        do {
            _ = try supabase()
            syncMessage = String(localized: "Ready")
            syncError = nil
        } catch {
            syncMessage = String(localized: "Needs setup")
            syncError = error.localizedDescription
        }
    }

    func syncNow(context: ModelContext,
                 conflictResolution: SyncCoordinator.ConflictResolution = .requireUserChoice) async {
        guard isSupabaseConfigured else {
            syncMessage = String(localized: "Offline")
            return
        }
        guard !isSyncing else {
            // A pass is already on the wire — run another when it finishes so
            // edits made mid-flight are pushed rather than dropped.
            followUpSyncRequested = true
            return
        }
        // Any pass supersedes a pending retry; an externally triggered one
        // (edit, foreground, realtime) also restarts the backoff ladder.
        retryTask?.cancel()
        if !invokedByRetry { retryAttempt = 0 }
        invokedByRetry = false
        // Demo rows seeded while sync was unconfigured must not leak into a
        // real workspace — drop the never-synced ones before the first push.
        SampleData.purgeAutoSeededDemoIfNeeded(context)
        let generation = syncGeneration
        isSyncing = true
        syncMessage = String(localized: "Syncing...")
        syncError = nil
        do {
            let client = try supabase()
            let profileStamp = profileEditGeneration
            let localProfile = WorkspaceProfilePayload(
                workspaceID: workspaceID,
                baseCurrencyCode: baseCurrencyCode,
                secondaryCurrencyCode: secondaryCurrencyCode,
                exchangeRate: rate
            )
            let remoteProfile = try await SyncCoordinator.syncWorkspaceProfile(
                client: client,
                workspaceID: workspaceID,
                local: localProfile,
                pushLocal: profileNeedsSync
            )
            guard generation == syncGeneration else {
                finishStaleSyncPass()
                return
            }
            if profileEditGeneration == profileStamp {
                applyRemoteWorkspaceProfile(remoteProfile)
            } else {
                // A currency edit landed while the request was in flight. Keep
                // it visible and push it in a follow-up pass.
                followUpSyncRequested = true
            }

            let nextCursor = try await SyncCoordinator.sync(context: context,
                                                            client: client,
                                                            workspaceID: workspaceID,
                                                            lastPulledAt: syncCursor,
                                                            conflictResolution: conflictResolution)
            guard generation == syncGeneration else {
                finishStaleSyncPass()
                return
            }
            syncCursor = nextCursor.rowUpdatedAt
            lastSyncAt = Date()
            syncMessage = String(localized: "Synced")
            try context.save()
            refreshPendingReminders(context: context)
            retryAttempt = 0
            lastSyncFailed = false
            syncConflictCount = 0
        } catch {
            guard generation == syncGeneration else {
                finishStaleSyncPass()
                return
            }
            context.rollback()
            if let conflict = error as? SyncCoordinator.SyncConflictError {
                syncConflictCount = conflict.count
                syncMessage = String(localized: "Resolve conflict")
                syncError = conflict.localizedDescription
                lastSyncFailed = false
            } else {
                syncMessage = String(localized: "Needs sync")
                syncError = error.localizedDescription
                lastSyncFailed = true
                scheduleRetrySync(context: context)
            }
        }
        isSyncing = false
        if followUpSyncRequested {
            followUpSyncRequested = false
            await syncNow(context: context)
        }
    }

    /// An in-flight pass outlived a workspace switch: drop its results and
    /// state writes. If a sync was requested for the *new* workspace while the
    /// stale pass held `isSyncing`, run it now against the current store.
    private func finishStaleSyncPass() {
        isSyncing = false
        if followUpSyncRequested {
            followUpSyncRequested = false
            if let context = realtimeContext { queueSync(context: context) }
        }
    }

    /// Replace the local SwiftData cache with the selected Supabase workspace.
    /// This intentionally does not enqueue tombstones: the user is switching
    /// sources of truth, not deleting remote income rows.
    @discardableResult
    func resetLocalDataAndPull(context: ModelContext) async -> String? {
        guard isSupabaseConfigured else {
            syncMessage = String(localized: "Offline")
            return String(localized: "Add the Supabase URL and publishable key first.")
        }
        syncGeneration += 1 // a pass already on the wire must not restore the old cursor
        queuedSyncTask?.cancel()
        retryTask?.cancel()
        followUpSyncRequested = false
        retryAttempt = 0
        invokedByRetry = false
        lastSyncFailed = false
        do {
            try clearLocalStore(context)
            syncCursor = nil
            lastSyncAt = nil
            defaults.set(false, forKey: SampleData.autoSeededDemoKey)
            await syncNow(context: context)
            return syncError
        } catch {
            syncMessage = String(localized: "Needs sync")
            syncError = error.localizedDescription
            return error.localizedDescription
        }
    }

    func queueSync(context: ModelContext) {
        queuedSyncTask?.cancel()
        queuedSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            self.refreshPendingReminders(context: context)
            await self.syncNow(context: context)
        }
    }

    /// The user has reviewed the conflict warning and intentionally wants this
    /// iPhone's dirty rows to replace the remote copies.
    func keepLocalConflictChanges(context: ModelContext) async {
        await syncNow(context: context, conflictResolution: .preferLocal)
    }

    func detachWorkspaceStore() {
        syncGeneration += 1
        queuedSyncTask?.cancel()
        retryTask?.cancel()
        configRefreshTask?.cancel()
        followUpSyncRequested = false
        retryAttempt = 0
        invokedByRetry = false
        lastSyncFailed = false
        realtimeContext = nil
        stopRealtime()
    }

    // MARK: Persistence

    /// The one persistence path: commit pending changes and kick the debounced
    /// sync. Returns `nil` on success, or a user-facing message on failure —
    /// assign it to the caller's error state and surface it with
    /// `.saveErrorAlert`. Every screen saves through here so the save + sync +
    /// error-reporting behaviour is identical everywhere.
    @discardableResult
    func save(_ context: ModelContext) -> String? {
        do {
            try context.save()
            queueSync(context: context)
            return nil
        } catch {
            // A save error must leave the screen exactly as it was before the
            // action. Without this rollback, a later unrelated save could
            // commit an insert/edit/delete the user was told had failed.
            context.rollback()
            return error.localizedDescription
        }
    }

    /// Delete an entry through the standard tombstone → save → undo flow, so a
    /// deletion looks the same whether it comes from the ledger, a client, or
    /// the pending list. Returns `nil` on success (with the undo staged) or the
    /// error message on failure.
    @discardableResult
    func delete(_ entry: Entry, context: ModelContext) -> String? {
        let snapshot = UndoableDelete.entry(EntrySnapshot(entry))
        SyncDeleteQueue.enqueue(.entry, id: entry.id, in: context)
        withAnimation(.snappy) { context.delete(entry) }
        let error = save(context)
        if error == nil { stageUndo(snapshot) }
        return error
    }

    /// Empty the local store — used by `resetLocalDataAndPull` when switching the
    /// source of truth to a different Supabase workspace.
    private func clearLocalStore(_ context: ModelContext) throws {
        for entry in try context.fetch(FetchDescriptor<Entry>()) {
            context.delete(entry)
        }
        for heading in try context.fetch(FetchDescriptor<Heading>()) {
            context.delete(heading)
        }
        for tombstone in try context.fetch(FetchDescriptor<SyncTombstone>()) {
            context.delete(tombstone)
        }
        for client in try context.fetch(FetchDescriptor<Client>()) {
            context.delete(client)
        }
        try context.save()
    }

    // MARK: Retry & reconnect

    /// A failed pass retries itself with growing delays, then gives up until
    /// the next external trigger (edit, foreground, realtime, reconnect) —
    /// endless polling against a dead endpoint would just burn battery.
    private func scheduleRetrySync(context: ModelContext) {
        guard let delay = Self.retryDelay(attempt: retryAttempt) else { return }
        retryAttempt += 1
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isSupabaseConfigured, !self.isSyncing else { return }
            self.invokedByRetry = true
            await self.syncNow(context: context)
        }
    }

    /// Backoff ladder: 5 s → 15 s → 45 s → 120 s, then nil (stop).
    nonisolated static func retryDelay(attempt: Int) -> Duration? {
        let delays: [Duration] = [.seconds(5), .seconds(15), .seconds(45), .seconds(120)]
        guard delays.indices.contains(attempt) else { return nil }
        return delays[attempt]
    }

    /// Sync as soon as connectivity returns after a failed pass, instead of
    /// sitting on "Needs sync" until the user happens to touch something.
    private func startPathMonitorIfNeeded() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathChange(satisfied: satisfied)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "earnline.path-monitor"))
    }

    private func handlePathChange(satisfied: Bool) {
        let cameBackOnline = satisfied && !pathWasSatisfied
        pathWasSatisfied = satisfied
        guard cameBackOnline, lastSyncFailed, let context = realtimeContext else { return }
        queueSync(context: context)
    }

    private func supabase() throws -> SupabaseClient {
        if let supabaseClient { return supabaseClient }
        let urlText = supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText), !key.isEmpty else {
            throw SyncError.missingConfiguration
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        supabaseClient = client
        return client
    }

    /// `internal` (not `private`) because the Supabase URL/key `didSet`s in the
    /// main file rebuild the client through here on every edit.
    func resetSupabaseClient() {
        supabaseClient = nil
        syncMessage = isSupabaseConfigured ? String(localized: "Ready") : String(localized: "Offline")
        scheduleConfigRefresh()
    }

    /// `internal` — the workspace/cursor `didSet`s in the main file key their
    /// UserDefaults through here.
    func workspaceDefaultKey(_ key: String) -> String {
        Self.workspaceDefaultKey(key, environment: workspaceEnvironment)
    }

    /// Swap the cached currency tuple together with the selected workspace.
    /// The cache is only an offline/first-frame value; a configured workspace
    /// always reconciles it against `earnline_profiles` during bootstrap.
    func loadWorkspaceCurrencyProfile() {
        isApplyingRemoteProfile = true
        let base = Self.normalizedCurrencyCode(
            defaults.string(forKey: workspaceDefaultKey("baseCurrencyCode")),
            fallback: Self.defaultBaseCurrencyCode
        )
        let secondary = Self.normalizedCurrencyCode(
            defaults.string(forKey: workspaceDefaultKey("secondaryCurrencyCode")),
            fallback: Self.defaultSecondaryCurrencyCode
        )
        baseCurrencyCode = base
        secondaryCurrencyCode = secondary == base
            ? Self.replacementCurrencyCode(excluding: base)
            : secondary
        let rateKey = workspaceDefaultKey("rate")
        let cachedRate = defaults.object(forKey: rateKey) == nil
            ? Self.defaultExchangeRate
            : defaults.double(forKey: rateKey)
        rate = Self.validExchangeRate(cachedRate)
        isApplyingRemoteProfile = false
    }

    /// `internal` — invoked from `workspaceEnvironment.didSet` in the main file.
    func loadWorkspaceSyncState() {
        lastSyncAt = defaults.object(forKey: workspaceDefaultKey("lastSyncAt")) as? Date
        syncCursor = defaults.object(forKey: workspaceDefaultKey("syncCursor")) as? Date
    }

    func loadWorkspaceProfileSyncState() {
        profileNeedsSync = defaults.bool(forKey: workspaceDefaultKey("profileNeedsSync"))
        profileEditGeneration += 1
    }

    func markWorkspaceProfileDirtyIfNeeded() {
        guard !isApplyingRemoteProfile else { return }
        profileNeedsSync = true
        profileEditGeneration += 1
        defaults.set(true, forKey: workspaceDefaultKey("profileNeedsSync"))
        if let context = realtimeContext { queueSync(context: context) }
    }

    private func applyRemoteWorkspaceProfile(_ profile: RemoteWorkspaceProfile) {
        isApplyingRemoteProfile = true
        baseCurrencyCode = profile.baseCurrencyCode
        secondaryCurrencyCode = profile.secondaryCurrencyCode
        rate = Self.validExchangeRate(profile.exchangeRate.doubleValue, fallback: rate)
        isApplyingRemoteProfile = false
        profileNeedsSync = false
        defaults.set(false, forKey: workspaceDefaultKey("profileNeedsSync"))
    }

    /// Load the Supabase URL/key for the active environment: the user's stored
    /// value for that workspace, or the project preloaded for it. Assigning
    /// these fires their `didSet`s, which persist the values under the new
    /// workspace's keys and rebuild the client. `internal` — called from
    /// `workspaceEnvironment.didSet` in the main file.
    func loadWorkspaceSupabaseConfig() {
        let config = workspaceEnvironment.defaultSupabaseConfig
        supabaseURLString = defaults.string(forKey: workspaceDefaultKey("supabaseURLString")) ?? config.url
        supabaseKey = defaults.string(forKey: workspaceDefaultKey("supabaseKey")) ?? config.publishableKey
    }

    /// The Settings fields fire their didSets on every keystroke — debounce
    /// before rebuilding the realtime subscription, and kick off a sync so a
    /// freshly configured workspace pulls without waiting for a manual "Sync
    /// now" or the next edit.
    private func scheduleConfigRefresh() {
        guard realtimeContext != nil else { return }
        configRefreshTask?.cancel()
        configRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.restartRealtime()
            if let context = self.realtimeContext, self.isSupabaseConfigured {
                await self.syncNow(context: context)
            }
        }
    }

    // MARK: Realtime

    /// Subscribe to workspace changes and trigger a debounced sync on any remote
    /// insert/update/delete. One schema-wide channel filtered by `workspace_id`
    /// covers ledger rows, tombstones, and the workspace profile.
    func startRealtime(context: ModelContext) {
        realtimeContext = context
        startPathMonitorIfNeeded()
        guard isSupabaseConfigured, realtimeChannel == nil, let client = try? supabase() else { return }
        let workspace = workspaceID
        let channel = client.channel("earnline:\(workspace)")
        realtimeChannel = channel
        realtimeClient = client
        let stream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            filter: .eq("workspace_id", value: workspace)
        )
        realtimeTask = Task { @MainActor [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                // Realtime is an optimization, not a reason to hide a failed
                // subscription. The next foreground/manual sync still works.
                self?.syncError = "Realtime updates unavailable: \(error.localizedDescription)"
            }
            for await _ in stream {
                self?.handleRealtimeChange()
            }
        }
    }

    private func handleRealtimeChange() {
        guard let realtimeContext else { return }
        queueSync(context: realtimeContext)
    }

    private func restartRealtime() {
        let context = realtimeContext
        stopRealtime()
        if let context { startRealtime(context: context) }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        // Tear down against the client that created the channel — after a
        // config change `supabaseClient` is already nil, and skipping the
        // removal leaked a live subscription per change.
        let client = realtimeClient
        realtimeClient = nil
        if let channel = realtimeChannel {
            realtimeChannel = nil
            Task { await client?.removeChannel(channel) }
        }
    }
}
