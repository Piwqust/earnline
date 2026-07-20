import Foundation
import Testing
@testable import earnline

@MainActor
@Suite(.serialized)
struct AccountStoreRecoveryTests {
    @Test func confirmedRecoveryUsesAnAccountScopedStoreWithoutTouchingTheLegacyStore() {
        let suiteName = "AccountStoreRecoveryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let app = AppModel(defaults: defaults)
        let workspaceID = "recovery-workspace"
        app.workspaceEnvironment = .production
        app.workspaceID = workspaceID
        app.accountStoreMode = .legacy
        app.workspaceStoreIdentity = "production:\(workspaceID):legacy"
        app.accountState = .ready(.init(
            userID: "owner-id",
            email: "owner@example.com",
            workspaceID: workspaceID,
            membershipRole: "owner",
            isPairedDevice: false
        ))

        #expect(app.canCreateFreshAccountStoreAfterRecovery)
        app.createFreshAccountStoreAfterRecovery()

        #expect(app.accountStoreMode == .account)
        #expect(app.workspaceStoreIdentity == "production:\(workspaceID):account")
        #expect(defaults.bool(forKey: "accountStoreMigrated.\(workspaceID)"))
    }

    @Test func recoveryNeverReplacesAGuestStore() {
        let suiteName = "AccountStoreRecoveryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let app = AppModel(defaults: defaults)
        app.accountState = .ready(.init(
            userID: "local-guest",
            email: nil,
            workspaceID: AppModel.localGuestWorkspaceID,
            membershipRole: "owner",
            isPairedDevice: false,
            isLocalOnly: true
        ))

        #expect(!app.canCreateFreshAccountStoreAfterRecovery)
        let originalMode = app.accountStoreMode
        app.createFreshAccountStoreAfterRecovery()
        #expect(app.accountStoreMode == originalMode)
    }

    @Test func offlineMembershipFallbackOnlyAcceptsTransportFailures() {
        #expect(AppModel.isOfflineTransportError(URLError(.notConnectedToInternet)))
        #expect(AppModel.isOfflineTransportError(URLError(.timedOut)))
        #expect(!AppModel.isOfflineTransportError(URLError(.userAuthenticationRequired)))
    }
}
