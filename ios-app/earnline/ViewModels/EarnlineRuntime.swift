import SwiftData

/// App Intents, background refresh, and SwiftUI share the same model and
/// container. Opening a second main context would leave visible rows stale.
@MainActor
final class EarnlineRuntime {
    static let shared = EarnlineRuntime()
    weak var app: AppModel?
    private var stores: [WorkspaceStore.Key: WorkspaceStore] = [:]

    func store(for key: WorkspaceStore.Key) throws -> WorkspaceStore {
        if let store = stores[key] { return store }
        let store = try WorkspaceStore(key: key)
        stores[key] = store
        return store
    }

    func ledger() throws -> (AppModel, ModelContext) {
        guard let app, app.isAccountReady else { throw IntentLedgerError.openAppFirst }
        return (app, try store(for: app.currentWorkspaceStoreKey).container.mainContext)
    }
}
