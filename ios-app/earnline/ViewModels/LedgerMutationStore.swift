import Observation
import SwiftData
import SwiftUI

/// Owns the local ledger mutation contract shared by every surface: a change
/// must save successfully before it advances derived summaries, schedules sync,
/// or offers undo. Keeping this boundary independent from authentication and
/// connection state makes failures auditable and prevents screen-specific
/// save/delete variants from drifting apart.
@MainActor
@Observable
final class LedgerMutationStore {
    /// Changes only after SwiftData accepted a write. Cached ledger summaries
    /// observe this instead of assuming every `ModelContext.didSave` came from
    /// a successful user mutation.
    private(set) var dataRevision = 0

    /// The most recent persisted delete, available for a short undo window.
    var undoableDelete: UndoableDelete?

    @ObservationIgnored private var undoExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleSync: (@MainActor (ModelContext) -> Void)?

    init() {}

    /// The composition root supplies the existing debounced sync scheduler
    /// after all shared stores are initialized. The mutation store never owns
    /// authentication or connection policy itself.
    func configureSyncScheduler(_ scheduler: @escaping @MainActor (ModelContext) -> Void) {
        scheduleSync = scheduler
    }

    /// A sync pull persists remote changes through its own transaction. It
    /// must still invalidate cached summaries, but it must not schedule another
    /// local push from inside the active sync pass.
    func recordExternalSave() {
        dataRevision &+= 1
    }

    /// Commit pending changes. A failed save rolls the context back so a later
    /// unrelated action cannot silently persist the rejected mutation.
    @discardableResult
    func save(_ context: ModelContext) -> String? {
        do {
            try context.save()
            dataRevision &+= 1
            scheduleSync?(context)
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    /// Delete an income line through the standard tombstone → save → undo
    /// flow. The undo toast is staged only once the delete is durable.
    @discardableResult
    func delete(_ entry: Entry, context: ModelContext) -> String? {
        let snapshot = UndoableDelete.entry(EntrySnapshot(entry))
        SyncDeleteQueue.enqueue(.entry, id: entry.id, in: context)
        withAnimation(.snappy) { context.delete(entry) }
        let error = save(context)
        if error == nil { stageUndo(snapshot) }
        return error
    }

    /// Call only after the delete has saved. A transient save failure must not
    /// produce an Undo control that cannot restore anything.
    func stageUndo(_ delete: UndoableDelete) {
        undoableDelete = delete
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undoableDelete = nil
        }
    }

    /// Drop a staged undo that no longer belongs to the store on screen.
    ///
    /// This object lives for the whole process, but a snapshot is a plain value
    /// captured from one specific SwiftData container. Signing out, switching
    /// accounts, or leaving guest mode inside the undo window would otherwise
    /// leave the toast live over a *different* workspace, and restoring a client
    /// there would insert it — with every entry it owned — as dirty rows that
    /// then sync into the wrong account. `AppModel.detachWorkspaceStore()` is
    /// the single funnel for every such switch and calls this.
    func discardStagedUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        undoableDelete = nil
    }

    /// Restore the snapshot and schedule sync only after the restore itself is
    /// durable. This mirrors the save failure contract used by new and edited
    /// rows.
    @discardableResult
    func performUndo(context: ModelContext) -> String? {
        guard let undoableDelete else { return nil }
        undoExpiryTask?.cancel()
        self.undoableDelete = nil
        do {
            try undoableDelete.restore(in: context)
            try context.save()
            dataRevision &+= 1
            scheduleSync?(context)
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    deinit {
        undoExpiryTask?.cancel()
    }
}
