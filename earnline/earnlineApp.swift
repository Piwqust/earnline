import SwiftUI
import SwiftData

@main
struct earnlineApp: App {
    @State private var app = AppModel()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Client.self, Entry.self, Heading.self, SyncTombstone.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SampleData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            LedgerView()
                .environment(app)
                .tint(Theme.blue)
                .task { await app.refreshSupabaseSession() }
        }
        .modelContainer(container)
    }
}
