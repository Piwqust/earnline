import Foundation
import SwiftData

/// One SwiftData container for one resolved workspace store. The view host
/// keeps one per environment for the app's lifetime; App Intents open a
/// matching container of their own when no scene is connected.
struct WorkspaceStore {
    struct Key: Hashable {
        let environment: AppModel.WorkspaceEnvironment
        let workspaceID: String
        let mode: AppModel.AccountStoreMode
    }

    let key: Key
    let container: ModelContainer

    var environment: AppModel.WorkspaceEnvironment { key.environment }

    init(key: Key) throws {
        self.key = key
        let schema = Schema(versionedSchema: EarnlineSchemaV3.self)
        // UI and unit tests must never open a person's old simulator store.
        // UI automation also seeds deterministic demo/stress fixtures. An
        // in-memory container keeps both test surfaces isolated and prevents
        // stale migration errors from polluting otherwise unrelated tests.
        let configuration = ModelConfiguration(
            Self.localStoreName(for: key),
            schema: schema,
            isStoredInMemoryOnly: AppModel.isRunningUIAutomation || AppModel.isRunningUnitTests
        )
        container = try ModelContainer(for: schema,
                                       migrationPlan: EarnlineMigrationPlan.self,
                                       configurations: configuration)
    }

    private static func localStoreName(for key: Key) -> String {
        // Preserve the existing production file for the approved legacy
        // handoff. Any other resolved workspace gets a different SwiftData
        // container, so switching accounts on one device cannot reuse data.
        if key.mode == .legacy { return key.environment.storeName }
        let safeWorkspaceID = key.workspaceID.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        return "\(key.environment.storeName)-\(String(safeWorkspaceID))"
    }
}

extension AppModel {
    /// The store the app would open for its current workspace identity.
    var currentWorkspaceStoreKey: WorkspaceStore.Key {
        WorkspaceStore.Key(environment: workspaceEnvironment, workspaceID: workspaceID, mode: accountStoreMode)
    }
}
