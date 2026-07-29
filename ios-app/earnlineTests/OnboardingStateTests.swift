import Foundation
import SwiftData
import Testing
@testable import earnline

/// The two pieces of state behind the first-run flow: the persisted
/// "this workspace has been introduced" flag, and the in-memory presentation
/// switch the root layer reads.
@MainActor
@Suite(.serialized)
struct OnboardingStateTests {
    private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) rethrows {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(AppModel(defaults: defaults), defaults)
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

    @Test func theFlagIsScopedToItsResolvedWorkspace() {
        withModel { app, defaults in
            app.onboardingCompleted = true

            let key = AppModel.onboardingDefaultKey(
                "onboardingCompleted",
                environment: app.workspaceEnvironment,
                workspaceID: app.workspaceID
            )
            #expect(defaults.bool(forKey: key))

            let otherKey = AppModel.onboardingDefaultKey(
                "onboardingCompleted",
                environment: app.workspaceEnvironment,
                workspaceID: "another-workspace"
            )
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

    @Test func anIncompleteFlowResumesFromItsDurableCheckpoint() {
        withModel { app, defaults in
            let clientID = UUID()
            let entryID = UUID()
            app.stageOnboardingClient(clientID)

            var relaunched = AppModel(defaults: defaults)
            #expect(relaunched.onboardingCheckpointStep == .income)
            #expect(relaunched.onboardingClientID == clientID)
            #expect(relaunched.onboardingEntryID == nil)

            relaunched.stageOnboardingEntry(entryID)
            relaunched = AppModel(defaults: defaults)
            #expect(relaunched.onboardingCheckpointStep == .done)
            #expect(relaunched.onboardingClientID == clientID)
            #expect(relaunched.onboardingEntryID == entryID)
        }
    }

    @Test func completionClearsTheDurableCheckpoint() {
        withModel { app, defaults in
            app.stageOnboardingClient(UUID())
            app.stageOnboardingEntry(UUID())
            app.completeOnboarding()

            let relaunched = AppModel(defaults: defaults)
            #expect(relaunched.onboardingCompleted)
            #expect(relaunched.onboardingCheckpointStep == .client)
            #expect(relaunched.onboardingClientID == nil)
            #expect(relaunched.onboardingEntryID == nil)
        }
    }

    @Test func existingLedgerDataSkipsFirstRunAndMigratesTheFlag() throws {
        try withModel { app, _ in
            let container = try ModelContainer(
                for: Client.self,
                Entry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            container.mainContext.insert(Client(name: "Existing client"))

            let presented = try app.resolveOnboardingPresentation(
                context: container.mainContext,
                remoteStateKnown: true
            )

            #expect(!presented)
            #expect(app.onboardingCompleted)
            #expect(!app.isPresentingOnboarding)
        }
    }

    @Test func anEmptyLedgerWaitsUntilRemoteStateIsKnown() throws {
        try withModel { app, _ in
            let container = try ModelContainer(
                for: Client.self,
                Entry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )

            #expect(try !app.resolveOnboardingPresentation(
                context: container.mainContext,
                remoteStateKnown: false
            ))
            #expect(!app.isPresentingOnboarding)

            #expect(try app.resolveOnboardingPresentation(
                context: container.mainContext,
                remoteStateKnown: true
            ))
            #expect(app.isPresentingOnboarding)
        }
    }
}
