import Foundation
import Testing
@testable import earnline

/// The two pieces of state behind the first-run flow: the persisted
/// "this workspace has been introduced" flag, and the in-memory presentation
/// switch the root layer reads.
@MainActor
@Suite(.serialized)
struct OnboardingStateTests {
    private func withModel(_ body: (AppModel, UserDefaults) -> Void) {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(AppModel(defaults: defaults), defaults)
    }

    @Test func aFreshWorkspaceHasNotBeenIntroduced() {
        withModel { app, _ in
            #expect(app.onboardingCompleted == false)
            #expect(app.isPresentingOnboarding == false)
        }
    }

    @Test func completionSurvivesRelaunch() {
        withModel { app, defaults in
            app.onboardingCompleted = true

            // The whole point of the flag: the second launch goes straight to
            // the ledger.
            let relaunched = AppModel(defaults: defaults)
            #expect(relaunched.onboardingCompleted)
        }
    }

    @Test func theFlagIsScopedToItsWorkspace() {
        withModel { app, defaults in
            // Dev builds are pinned to Test, so drive the key directly rather
            // than flipping `workspaceEnvironment`, which a DEBUGMENU build
            // refuses to move off `.test`.
            let environment = app.workspaceEnvironment
            app.onboardingCompleted = true

            let key = AppModel.workspaceDefaultKey("onboardingCompleted", environment: environment)
            #expect(defaults.bool(forKey: key))

            let other: AppModel.WorkspaceEnvironment = environment == .production ? .test : .production
            let otherKey = AppModel.workspaceDefaultKey("onboardingCompleted", environment: other)
            #expect(defaults.bool(forKey: otherKey) == false)
        }
    }

    @Test func presentationIsNotPersisted() {
        withModel { app, defaults in
            app.isPresentingOnboarding = true

            // It describes what is on screen right now. A relaunch that
            // restored it would re-run a flow the owner already finished.
            let relaunched = AppModel(defaults: defaults)
            #expect(relaunched.isPresentingOnboarding == false)
            #expect(app.isPresentingOnboarding)
        }
    }

    @Test func theHandoffIsNotPersisted() {
        withModel { app, defaults in
            let id = UUID()
            app.pendingFirstEntryClientID = id

            // A stale value read back on a later launch would reopen a composer
            // nobody asked for, so it must live in memory only.
            let fresh = AppModel(defaults: defaults)
            #expect(fresh.pendingFirstEntryClientID == nil)
            #expect(app.pendingFirstEntryClientID == id)
        }
    }
}
