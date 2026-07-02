import SwiftUI
import SwiftData

@main
struct earnlineApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var app: AppModel
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Schema(versionedSchema: EarnlineSchemaV1.self),
                                           migrationPlan: EarnlineMigrationPlan.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let model = AppModel()
        _app = State(initialValue: model)
        // Demo data exists so an unconfigured first launch feels alive; a
        // device pointed at a real workspace must start from the remote truth.
        if !model.isSupabaseConfigured {
            SampleData.seedIfNeeded(container.mainContext)
            SampleData.importBundledLedgerIfNeeded(container.mainContext)
        }
        SampleData.cleanupLegacyDemoEntriesIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            LedgerView()
                .environment(app)
                .tint(Theme.blue)
                .preferredColorScheme(app.prefersDarkMode ? .dark : .light)
                .task {
                    await app.refreshSupabaseSession()
                    await app.syncNow(context: container.mainContext)
                    app.refreshPendingReminders(context: container.mainContext)
                    app.startRealtime(context: container.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Returning to the foreground pulls whatever happened while
                    // the socket was suspended.
                    guard phase == .active, !app.isSyncing else { return }
                    Task { await app.syncNow(context: container.mainContext) }
                }
        }
        .modelContainer(container)
    }
}
