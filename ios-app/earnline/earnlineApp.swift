import SwiftUI
import SwiftData

@main
struct earnlineApp: App {
    @State private var app: AppModel

    init() {
        let model = AppModel()
        _app = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceContainerHost(app: app)
        }
    }
}

private struct WorkspaceContainerHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: AppModel
    /// One container per environment, kept for the app's lifetime. Switching
    /// workspaces must NOT release the outgoing container: the old view tree
    /// is still mid-teardown and SwiftData invalidates every model registered
    /// with a deallocated container — any `EntryRow` that redrew during the
    /// transition then trapped in a model getter (the "switch twice and it
    /// crashes" bug). Caching also makes switching back instant.
    @State private var stores: [AppModel.WorkspaceEnvironment: WorkspaceStore]
    @State private var activeEnvironment: AppModel.WorkspaceEnvironment

    init(app: AppModel) {
        self.app = app
        let environment = app.workspaceEnvironment
        do {
            _stores = State(initialValue: [environment: try WorkspaceStore(environment: environment)])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        _activeEnvironment = State(initialValue: environment)
    }

    private var store: WorkspaceStore {
        guard let store = stores[activeEnvironment] else {
            fatalError("No store for \(activeEnvironment)")
        }
        return store
    }

    var body: some View {
        @Bindable var app = app
        LedgerView()
            .id(store.environment)
            // Settings is presented here, outside the `.id` boundary, so a
            // workspace switch made *from inside Settings* swaps the ledger
            // underneath without dismissing the sheet the user is touching.
            .sheet(isPresented: $app.showSettings) { SettingsView() }
            .environment(app)
            .modelContainer(store.container)
            .tint(app.accentColor)
            // Honor Reduce Motion app-wide: every explicit `.animation` /
            // `withAnimation` in the tree routes its transaction through here,
            // so stripping the animation collapses them all to instant state
            // changes without touching each call site.
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
            // Appearance is enforced via UIWindow.overrideUserInterfaceStyle
            // (see AppModel.applyAppearance) — deliberately NOT via
            // .preferredColorScheme, which pins already-presented sheets to
            // the scheme captured when they were presented.
            .onAppear(perform: app.applyAppearance)
            .task(id: store.environment) {
                await bootstrapCurrentStore()
            }
            .onChange(of: app.workspaceEnvironment) { _, environment in
                switchStore(to: environment)
            }
            .onChange(of: scenePhase) { _, phase in
                guard !AppModel.isRunningUIAutomation else { return }
                // Cover on `.inactive` (before the app-switcher snapshot),
                // commit the lock only on `.background`.
                if phase == .inactive { app.coverIfNeeded() }
                if phase == .background { app.lockIfNeeded() }
                guard phase == .active else { return }
                // A window created while backgrounded starts on the system
                // scheme; re-assert the in-app choice on every activation.
                app.applyAppearance()
                app.uncoverIfNeeded()
                app.attemptUnlockIfNeeded()
                // Returning to the foreground pulls whatever happened while
                // the socket was suspended.
                guard !app.isSyncing else { return }
                Task { await app.syncNow(context: store.container.mainContext) }
            }
    }

    @MainActor
    private func bootstrapCurrentStore() async {
        let context = store.container.mainContext
        if AppModel.isRunningUIAutomation {
            // Keep smoke tests deterministic and isolated from the user's
            // personal Supabase workspace. The test only verifies navigation
            // and visible controls, so it does not need a live sync.
            return
        }
        app.lockOnLaunchIfNeeded()
        // Demo data exists so an unconfigured first launch feels alive; a
        // device pointed at a real workspace must start from the remote truth.
        if !app.isSupabaseConfigured {
            SampleData.seedIfNeeded(context)
            SampleData.importBundledLedgerIfNeeded(context)
        }
        SampleData.cleanupLegacyDemoEntriesIfNeeded(context)
        await app.refreshSupabaseSession()
        await app.syncNow(context: context)
        app.refreshPendingReminders(context: context)
        app.startRealtime(context: context)
    }

    private func switchStore(to environment: AppModel.WorkspaceEnvironment) {
        app.detachWorkspaceStore()
        if stores[environment] == nil {
            do {
                stores[environment] = try WorkspaceStore(environment: environment)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
        activeEnvironment = environment
    }
}

private struct WorkspaceStore {
    let environment: AppModel.WorkspaceEnvironment
    let container: ModelContainer

    init(environment: AppModel.WorkspaceEnvironment) throws {
        self.environment = environment
        let schema = Schema(versionedSchema: EarnlineSchemaV1.self)
        let configuration = ModelConfiguration(environment.storeName, schema: schema)
        container = try ModelContainer(for: schema,
                                       migrationPlan: EarnlineMigrationPlan.self,
                                       configurations: configuration)
    }
}
