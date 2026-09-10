import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct earnlineApp: App {
    @UIApplicationDelegateAdaptor(EarnlineAppDelegate.self) private var appDelegate
    @State private var app: AppModel

    init() {
        let defaults: UserDefaults
        #if DEBUG
        if AppModel.isRunningUIAutomation || AppModel.isRunningUnitTests,
           let isolatedDefaults = UserDefaults(suiteName: AppModel.uiAutomationDefaultsSuite) {
            isolatedDefaults.removePersistentDomain(forName: AppModel.uiAutomationDefaultsSuite)
            defaults = isolatedDefaults
        } else {
            defaults = .standard
        }
        #else
        defaults = .standard
        #endif
        let model = AppModel(defaults: defaults)
        EarnlineRuntime.shared.app = model
        BackgroundLedgerRefresh.register()
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
    @State private var stores: [WorkspaceStore.Key: WorkspaceStore]
    @State private var activeStoreKey: WorkspaceStore.Key
    /// A store-open failure must never take the whole application down. The
    /// original SQLite files stay untouched while the owner chooses whether to
    /// retry or, after authentication, start an isolated cloud-backed cache.
    @State private var storeOpenError: String?

    init(app: AppModel) {
        self.app = app
        let key = WorkspaceStore.Key(environment: app.workspaceEnvironment, workspaceID: app.workspaceID, mode: app.accountStoreMode)
        do {
            _stores = State(initialValue: [key: try EarnlineRuntime.shared.store(for: key)])
            _storeOpenError = State(initialValue: nil)
        } catch {
            _stores = State(initialValue: [:])
            _storeOpenError = State(initialValue: error.localizedDescription)
        }
        _activeStoreKey = State(initialValue: key)
    }

    private struct SystemSurfaceRevision: Hashable {
        let identity: String
        let revision: Int
        let rate: Double
        let locked: Bool
        let accountReady: Bool
        let base: String
        let secondary: String
    }

    private var store: WorkspaceStore? { stores[activeStoreKey] }

    var body: some View {
        @Bindable var app = app
        Group {
            if let store {
                ZStack {
                    primaryContent(for: store)
                }
                    .animation(.easeInOut(duration: 0.22), value: app.isAccountReady)
                    // Settings is presented here, outside the `.id` boundary, so a
                    // workspace switch made *from inside Settings* swaps the ledger
                    // underneath without dismissing the sheet the user is touching.
                    .sheet(isPresented: $app.showSettings) { SettingsView() }
                    .modelContainer(store.container)
                    .task(id: activeStoreKey) {
                        #if DEBUGMENU
                        // Keep the anywhere-accessible debug overlay pointed at the
                        // container the app is actually rendering.
                        DebugMenuOverlay.install(app: app, container: store.container)
                        #endif
                        await bootstrapCurrentStore(store: store)
                    }
                    .task(id: SystemSurfaceRevision(identity: app.workspaceStoreIdentity,
                                                    revision: app.mutations.dataRevision,
                                                    rate: app.rate, locked: app.requireAppLock,
                                                    accountReady: app.isAccountReady,
                                                    base: app.baseCurrencyCode, secondary: app.secondaryCurrencyCode)) {
                        guard store.key == app.currentWorkspaceStoreKey else { return }
                        await LedgerSystemSurfaces.refresh(app: app, context: store.container.mainContext)
                    }
                    .onContinueUserActivity(CSSearchableItemActionType) { activity in
                        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                              identifier.hasPrefix(app.workspaceStoreIdentity + "|"),
                              let id = identifier.split(separator: "|").last.flatMap({ UUID(uuidString: String($0)) }) else { return }
                        app.spotlightEntryID = id
                    }
                    .onChange(of: scenePhase) { _, phase in
                        handleScenePhase(phase, store: store)
                    }
            } else {
                unavailableStoreContent
                    .task(id: activeStoreKey) {
                        await app.bootstrapAuthentication()
                    }
            }
        }
            .environment(app)
            .environment(app.mutations)
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
            .onChange(of: app.workspaceEnvironment) { _, environment in
                switchStore(to: environment, workspaceID: app.workspaceID, mode: app.accountStoreMode)
            }
            .onChange(of: app.workspaceStoreIdentity) {
                switchStore(to: app.workspaceEnvironment, workspaceID: app.workspaceID, mode: app.accountStoreMode)
            }
            .onOpenURL { url in
                Task { await app.handleAppURL(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .earnlineQuickAction)) { _ in
                app.consumeQuickAction()
            }
    }

    @ViewBuilder
    private func primaryContent(for store: WorkspaceStore) -> some View {
        // One gate, both builds. A Dev-only account preview drives the *real*
        // `AuthGateView` through `AppModel.accountState`; it does not swap in a
        // second, look-alike screen. See the `isDebugAuthGatePreview` guards in
        // `AppModel+Auth`, which keep every action inert while it runs.
        if app.isAccountReady {
            ledger(for: store)
        } else {
            AuthGateView()
                .transition(.opacity)
        }
    }

    /// The ledger, with the first-run flow layered over it when it is due.
    ///
    /// Onboarding is a sibling layer rather than a cover because its last
    /// screen *is* the ledger: the owner's new client and first line are
    /// already behind the "You're all set!" scrim. Keeping the real view
    /// mounted underneath also means its bootstrap has run by the time the
    /// flow hands over.
    @ViewBuilder
    private func ledger(for store: WorkspaceStore) -> some View {
        ZStack {
            LedgerView()
                .id(store.key)
                .allowsHitTesting(!app.isPresentingOnboarding)
                .accessibilityHidden(app.isPresentingOnboarding)

            if app.isPresentingOnboarding {
                OnboardingFlowView {
                    app.completeOnboarding()
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: app.isPresentingOnboarding)
        .transition(.opacity)
    }

    @ViewBuilder
    private var unavailableStoreContent: some View {
        // A store that will not open is only recoverable once we know whose
        // ledger it is. Until then the gate stays in front of it.
        if app.isAccountReady {
            StoreRecoveryView(
                canCreateFreshAccountStore: app.canCreateFreshAccountStoreAfterRecovery,
                retry: retryActiveStore,
                createFreshAccountStore: {
                    app.createFreshAccountStoreAfterRecovery()
                }
            )
        } else {
            AuthGateView()
        }
    }

    @MainActor
    private func bootstrapCurrentStore(store: WorkspaceStore) async {
        let context = store.container.mainContext
        #if DEBUG
        if AppModel.isRunningUIAutomation {
            // The gate's own tests need the real authentication surface, in a
            // deterministic state, with no fixtures seeded behind it.
            if AppModel.isAuthGatePreview {
                await app.bootstrapAuthentication()
                return
            }
            // Keep smoke tests deterministic and isolated from the user's
            // personal Supabase workspace. Insights visual/UI tests explicitly
            // request the deterministic generated ledger; other tests remain
            // empty and fast.
            if AppModel.hasUIAutomationLaunchFlag("-demoInsights")
                || AppModel.hasUIAutomationLaunchFlag("-demoLedger")
                || AppModel.hasUIAutomationLaunchFlag("-demoClientProfileCompact") {
                _ = try? SampleData.seedGenerated(context)
            } else if AppModel.hasUIAutomationLaunchFlag("-demoClientProfile")
                || AppModel.hasUIAutomationLaunchFlag("-demoStressLedger") {
                SampleData.seedStress(context)
            } else if AppModel.hasUIAutomationLaunchFlag("-demoComposer") {
                SampleData.seed(context)
            }
            // The client-profile harness exists to exercise the achievement
            // collection itself. Keep this test-only fixture self-contained
            // instead of depending on a setting left behind by another test.
            if AppModel.hasUIAutomationLaunchFlag("-demoClientProfile") {
                app.clientBadgesEnabled = true
            }
            // UI automation runs on a wiped defaults suite, so every test would
            // otherwise launch into the first-run flow. It is opt-in here and
            // opt-in only.
            if AppModel.hasUIAutomationLaunchFlag("-demoOnboarding") {
                app.isPresentingOnboarding = true
            }
            return
        }
        #endif
        app.lockOnLaunchIfNeeded()
        let initialStoreIdentity = app.workspaceStoreIdentity
        await app.bootstrapAuthentication()
        // Resolving an account can switch from the legacy container to a
        // private, account-scoped one. Let the new container's task own the
        // first sync; never push the old container under the new membership.
        guard initialStoreIdentity == app.workspaceStoreIdentity, app.isAccountReady else { return }
        if store.environment == .production {
            do {
                try SampleData.cleanupLeakedProductionFixturesIfNeeded(context)
            } catch {
                app.syncMessage = String(localized: "Needs sync")
                app.syncError = "Could not remove leaked test fixtures: \(error.localizedDescription)"
                return
            }
        }
        // Test is deliberately local-only. Production does not seed into a
        // signed-out account gate, so demo rows can never leak through OAuth.
        // The production guest store also starts empty: it is a real ledger,
        // not a demo, and must never hold rows the user didn't write.
        if !app.isSupabaseConfigured, app.accountSession?.isLocalOnly != true {
            SampleData.seedIfNeeded(context)
        }
        do {
            try SampleData.cleanupLegacyDemoEntriesIfNeeded(context)
        } catch {
            app.syncMessage = String(localized: "Needs sync")
            // swiftlint:disable:next line_length
            app.syncError = String(localized: "Earnline could not safely finish local ledger cleanup. Nothing was uploaded. Restart the app and try again.")
            return
        }
        let syncOutcome = await app.syncNow(context: context)
        // A successful first authenticated pass may move the app from its
        // legacy cache to an account-scoped container. The new container's
        // bootstrap owns onboarding; never decide from the outgoing cache.
        guard initialStoreIdentity == app.workspaceStoreIdentity else { return }

        let remoteStateKnown = syncOutcome == nil
            || app.accountSession?.isLocalOnly == true
            || store.environment != .production
        do {
            try app.resolveOnboardingPresentation(
                context: context,
                remoteStateKnown: remoteStateKnown
            )
        } catch {
            app.isPresentingOnboarding = false
            app.syncMessage = String(localized: "Needs sync")
            // swiftlint:disable:next line_length
            app.syncError = String(localized: "Earnline could not safely decide whether onboarding is needed. Your ledger was not changed. Restart the app and try again.")
            return
        }
        app.refreshPendingReminders(context: context)
        app.startRealtime(context: context)
    }

    private func switchStore(to environment: AppModel.WorkspaceEnvironment,
                             workspaceID: String,
                             mode: AppModel.AccountStoreMode) {
        let key = WorkspaceStore.Key(environment: environment, workspaceID: workspaceID, mode: mode)
        app.detachWorkspaceStore()
        // A pending composer handoff never crosses a workspace boundary: the
        // client it names lives in the store being switched away from.
        if stores[key] == nil {
            do {
                stores[key] = try EarnlineRuntime.shared.store(for: key)
                storeOpenError = nil
            } catch {
                activeStoreKey = key
                storeOpenError = error.localizedDescription
                return
            }
        }
        activeStoreKey = key
        storeOpenError = nil
    }

    private func retryActiveStore() {
        guard stores[activeStoreKey] == nil else { return }
        do {
            stores[activeStoreKey] = try EarnlineRuntime.shared.store(for: activeStoreKey)
            storeOpenError = nil
        } catch {
            storeOpenError = error.localizedDescription
        }
    }

    private func handleScenePhase(_ phase: ScenePhase, store: WorkspaceStore) {
        guard !AppModel.isRunningUIAutomation else { return }
        // Cover on `.inactive` (before the app-switcher snapshot), commit the
        // lock only on `.background`.
        if phase == .inactive { app.coverIfNeeded() }
        if phase == .background {
            app.lockIfNeeded()
            BackgroundLedgerRefresh.scheduleIfNeeded(app: app)
        }
        guard phase == .active else { return }
        // A window created while backgrounded starts on the system scheme;
        // re-assert the in-app choice on every activation.
        app.applyAppearance()
        app.uncoverIfNeeded()
        app.attemptUnlockIfNeeded()
        // Returning to the foreground pulls whatever happened while the socket
        // was suspended.
        app.consumeQuickAction()
        if app.pendingQuickAction == nil, LedgerSystemSurfaces.sharedText() != nil {
            app.pendingQuickAction = .pasteLines
        }
        guard app.isAccountReady, !app.isSyncing else { return }
        Task { await app.syncNow(context: store.container.mainContext) }
    }
}

/// A failed SwiftData migration used to terminate the process before the
/// account gate could appear. This recovery surface intentionally offers no
/// deletion: the old SQLite files remain in place until a later, explicit
/// import or support-led migration.
private struct StoreRecoveryView: View {
    let canCreateFreshAccountStore: Bool
    let retry: () -> Void
    let createFreshAccountStore: () -> Void

    @State private var isConfirmingFreshStore = false

    var body: some View {
        ContentUnavailableView {
            Label("Your local ledger needs recovery", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Earnline could not open this older local copy. Its files have not been changed or deleted.")
        } actions: {
            VStack(spacing: 12) {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)

                if canCreateFreshAccountStore {
                    Button("Create a new local cache") {
                        isConfirmingFreshStore = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .accessibilityIdentifier("store.recovery")
        .confirmationDialog(
            "Create a new local cache?",
            isPresented: $isConfirmingFreshStore,
            titleVisibility: .visible
        ) {
            Button("Create new cache") {
                createFreshAccountStore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // swiftlint:disable:next line_length
            Text("Your older local ledger will stay on this device untouched. Earnline will use a separate cache for your signed-in workspace, which you can populate by syncing or importing later.")
        }
    }
}
