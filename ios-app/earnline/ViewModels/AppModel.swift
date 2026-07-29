import SwiftUI
import Observation
import SwiftData
import Supabase
import Network

/// App-wide UI state + currency settings (persisted in UserDefaults).
@MainActor
@Observable
final class AppModel {
    /// The side-by-side `earnline Dev` target is a companion for local UI
    /// work, never a second client for a production workspace. Keeping this
    /// compile-time (rather than a stored preference) means a clean Dev
    /// install cannot inherit a production choice from anywhere.
    nonisolated static var isLocalOnlyDevBuild: Bool {
        #if DEBUGMENU
        true
        #else
        false
        #endif
    }

    /// UI automation must not inherit a real device's lock state or start a
    /// live personal-workspace sync. This launch argument is set exclusively by
    /// the UI-test target and leaves normal app launches unchanged.
    ///
    /// XCUITest can retain a previous process's launch arguments while it
    /// relaunches the same bundle in a long serial suite. Its per-launch
    /// environment is authoritative, so test helpers set a complete flag set
    /// there; command-line arguments remain the fallback for manual runs.
    #if DEBUG
    nonisolated static let uiTestFlagsEnvironmentKey = "EARNLINE_UI_TEST_FLAGS"
    nonisolated static let uiAutomationDefaultsSuite = "com.earnline.app.ui-tests"
    #endif

    nonisolated static func hasUIAutomationLaunchFlag(_ flag: String) -> Bool {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        if let rawFlags = processInfo.environment[uiTestFlagsEnvironmentKey] {
            return rawFlags
                .split(whereSeparator: { $0 == " " || $0 == "\n" })
                .contains { $0 == flag }
        }
        return processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }

    nonisolated static var isRunningUIAutomation: Bool {
        #if DEBUG
        hasUIAutomationLaunchFlag("-uiTesting")
            || hasUIAutomationLaunchFlag("-demoLedger")
            || hasUIAutomationLaunchFlag("-demoStressLedger")
        #else
        false
        #endif
    }
    /// Swift Testing exercises the App Lock state machine directly, but its
    /// ephemeral host window never receives a full scene appearance cycle.
    /// Creating a second alert-level window there produces UIKit's spurious
    /// unbalanced-transition warning; real app and UI-test launches keep the
    /// production window path intact.
    nonisolated static var isRunningUnitTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && !isRunningUIAutomation
        #else
        false
        #endif
    }
    nonisolated static let supportedCurrencyCodes = Limits.supportedCurrencyCodes
    nonisolated static let defaultBaseCurrencyCode = "USD"
    nonisolated static let defaultSecondaryCurrencyCode = "RUB"
    nonisolated static let defaultExchangeRate = 83.0
    /// Local sentinels only. A real production workspace is resolved from the
    /// authenticated membership RPC and is never committed to source.
    nonisolated static let productionWorkspaceID = "legacy-production-cache"
    nonisolated static let testWorkspaceID = "local-test-cache"
    nonisolated static let workspaceCurrencyProfileStorageVersion = 1

    enum WorkspaceEnvironment: String, CaseIterable, Identifiable {
        case production
        case test

        var id: String { rawValue }

        var workspaceID: String {
            switch self {
            case .production: AppModel.productionWorkspaceID
            case .test: AppModel.testWorkspaceID
            }
        }

        var title: String {
            switch self {
            case .production: String(localized: "Production")
            case .test: String(localized: "Test")
            }
        }

        /// Preloaded Supabase project this environment syncs to. Production and
        /// Test point at separate Supabase databases, so their rows never mix.
        var defaultSupabaseConfig: SupabaseProjectDefaults.ProjectConfig {
            switch self {
            case .production: SupabaseProjectDefaults.production
            case .test: SupabaseProjectDefaults.test
            }
        }

        var storeName: String { "earnline-\(rawValue)" }
    }

    enum AccountStoreMode: String, Hashable {
        /// The old, unscoped SwiftData container. It is preserved through the
        /// first authenticated push and is never deleted by this migration.
        case legacy
        /// A workspace-specific container populated from the first successful
        /// authenticated pull.
        case account
    }

    /// The durable checkpoint for the first-run flow. The rows created by the
    /// flow are real ledger data, so the checkpoint must survive a process
    /// termination and resume instead of attempting to create them again.
    enum OnboardingCheckpointStep: Int {
        case client, income, done
    }

    var baseCurrencyCode: String {
        didSet {
            let normalized = Self.normalizedCurrencyCode(baseCurrencyCode, fallback: oldValue)
            if baseCurrencyCode != normalized {
                baseCurrencyCode = normalized
                return
            }
            if secondaryCurrencyCode == baseCurrencyCode {
                secondaryCurrencyCode = Self.replacementCurrencyCode(excluding: baseCurrencyCode)
            }
            defaults.set(baseCurrencyCode, forKey: workspaceDefaultKey("baseCurrencyCode"))
            markWorkspaceProfileDirtyIfNeeded()
        }
    }
    var secondaryCurrencyCode: String {
        didSet {
            let normalized = Self.normalizedCurrencyCode(secondaryCurrencyCode, fallback: oldValue)
            if secondaryCurrencyCode != normalized {
                secondaryCurrencyCode = normalized
                return
            }
            if secondaryCurrencyCode == baseCurrencyCode {
                secondaryCurrencyCode = Self.replacementCurrencyCode(excluding: baseCurrencyCode)
                return
            }
            defaults.set(secondaryCurrencyCode, forKey: workspaceDefaultKey("secondaryCurrencyCode"))
            markWorkspaceProfileDirtyIfNeeded()
        }
    }
    /// Secondary units per 1 base unit (e.g. RUB per USD).
    var rate: Double {
        didSet {
            let normalized = Self.validExchangeRate(rate, fallback: oldValue)
            if rate != normalized {
                rate = normalized
                return
            }
            defaults.set(rate, forKey: workspaceDefaultKey("rate"))
            markWorkspaceProfileDirtyIfNeeded()
        }
    }
    var supabaseURLString: String {
        didSet {
            defaults.set(supabaseURLString, forKey: workspaceDefaultKey("supabaseURLString"))
            resetSupabaseClient()
        }
    }
    var supabaseKey: String {
        didSet {
            defaults.set(supabaseKey, forKey: workspaceDefaultKey("supabaseKey"))
            resetSupabaseClient()
        }
    }
    var workspaceEnvironment: WorkspaceEnvironment {
        didSet {
            if Self.isLocalOnlyDevBuild, workspaceEnvironment != .test {
                workspaceEnvironment = .test
                return
            }
            guard workspaceEnvironment != oldValue else { return }
            defaults.set(workspaceEnvironment.rawValue, forKey: "workspaceEnvironment")
            workspaceID = defaults.string(forKey: "workspaceID.\(workspaceEnvironment.rawValue)")
                ?? workspaceEnvironment.workspaceID
            defaults.set(workspaceID, forKey: "workspaceID")
            accountStoreMode = defaults.bool(forKey: "accountStoreMigrated.\(workspaceID)") ? .account : .legacy
            workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):\(workspaceID):\(accountStoreMode.rawValue)"
            // Each environment points at its own Supabase project — swap the
            // URL/key over to the new one before rebuilding the client.
            loadWorkspaceSupabaseConfig()
            loadWorkspaceCurrencyProfile()
            loadWorkspaceSyncState()
            loadWorkspaceProfileSyncState()
            // Each resolved workspace earns its own introduction. Currency
            // preferences are environment-scoped, but onboarding cannot be:
            // two accounts can use the same Production environment.
            loadOnboardingState(migrateLegacyFlag: true)
            detachWorkspaceStore()
            resetSupabaseClient()
        }
    }
    var workspaceID: String
    /// Changes whenever a resolved account must use a different local SwiftData
    /// container. The host observes this instead of letting a newly-signed-in
    /// account render a previous account's cache.
    var workspaceStoreIdentity: String
    var accountStoreMode: AccountStoreMode

    /// System / Light / Dark — the standard three-way appearance choice Apple
    /// apps offer. `system` follows the device scheme (`.unspecified`).
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: String(localized: "System")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            }
        }

        var uiStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }
    /// Accent for interactive elements — ChatGPT's "Accent color" setting.
    /// Applied at the root via `.tint`, so everything tint-following updates.
    var accent: Theme.Accent {
        didSet { defaults.set(accent.rawValue, forKey: "accentColor") }
    }
    var accentColor: Color { accent.color }
    /// Advanced controls affect both Settings and the ledger chrome, so the
    /// preference belongs to the app model and survives sheet recreation and
    /// relaunches. UI automation explicitly resets it with a launch argument.
    var developerModeEnabled: Bool {
        didSet { defaults.set(developerModeEnabled, forKey: "developerModeEnabled") }
    }
    /// Client badges are still being evaluated, so they stay off by default
    /// and are only configurable from the Experimental developer section.
    var clientBadgesEnabled: Bool {
        didSet { defaults.set(clientBadgesEnabled, forKey: "clientBadgesEnabled") }
    }
    /// Face ID / passcode lock on backgrounding — opt-in via Settings.
    var requireAppLock: Bool {
        didSet { defaults.set(requireAppLock, forKey: "requireAppLock") }
    }
    /// Whether this resolved workspace has been through the first-run flow.
    /// Unlike currency preferences, this key includes `workspaceID`: signing
    /// into a second account in Production must not inherit the first account's
    /// introduction.
    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: onboardingDefaultKey("onboardingCompleted")) }
    }
    var onboardingCheckpointStep: OnboardingCheckpointStep = .client {
        didSet {
            defaults.set(
                onboardingCheckpointStep.rawValue,
                forKey: onboardingDefaultKey("onboardingCheckpointStep")
            )
        }
    }
    var onboardingClientID: UUID? {
        didSet { persist(onboardingClientID, forKey: onboardingDefaultKey("onboardingClientID")) }
    }
    var onboardingEntryID: UUID? {
        didSet { persist(onboardingEntryID, forKey: onboardingDefaultKey("onboardingEntryID")) }
    }
    /// Whether the onboarding layer is on screen. In-memory only: it is a
    /// presentation state, not a preference, and it is derived from
    /// `onboardingCompleted` at launch. Replaying from Settings or the debug
    /// menu sets it directly without disturbing the persisted flag.
    var isPresentingOnboarding = false
    private(set) var isLocked = false
    /// A non-blocking privacy message shown in Settings after the app disables
    /// an impossible legacy lock (for example, after the device passcode was
    /// removed). The ledger is never left behind a cover it cannot unlock.
    var appLockNotice: String?
    /// A non-blocking warning about account or workspace verification. It
    /// never replaces the visible recovery path or erases the local ledger.
    var accountSecurityNotice: String?
    var isSyncing = false
    var syncMessage = String(localized: "Offline")
    /// Increments only after a ledger mutation has reached SwiftData. Views
    /// with cached derived data use this explicit signal rather than relying
    /// exclusively on a process-wide save notification.
    var ledgerDataRevision = 0
    var syncError: String?
    var accountState: AccountState = .checking
    #if DEBUGMENU
    /// A Dev-only account-screen simulator. It never creates, clears, or
    /// changes a real authentication session; it only replaces the visible
    /// ledger with an explicitly requested local preview.
    var debugAuthGatePreview = false
    var debugAuthPreviewProviderName: String?
    @ObservationIgnored var debugAccountStateBeforePreview: AccountState?
    #endif
    /// Number of remote edits/deletes that changed after this device's last
    /// observed server version. These require an explicit user choice rather
    /// than a silent last-device-wins overwrite. Written by the sync pass in
    /// `AppModel+Sync.swift`; module-internal setter (only that extension
    /// writes it — views read it).
    var syncConflictCount = 0
    /// When the last sync completed — display only ("Last sync" in Settings).
    var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt, forKey: workspaceDefaultKey("lastSyncAt")) }
    }
    /// Incremental cursor for server-managed row `updated_at` values.
    var syncCursor: Date? {
        didSet { defaults.set(syncCursor, forKey: workspaceDefaultKey("syncCursor")) }
    }
    var workspaceDisplayName: String {
        workspaceEnvironment.title
    }

    /// The month currently under the top of the scroll — shown in the summary pill.
    var displayedMonth: Date = DateFormat.monthStart(of: .now)

    /// Whether the Settings sheet is up. Lives here — and the sheet is
    /// presented from `WorkspaceContainerHost` — because switching the
    /// workspace recreates `LedgerView` via `.id`, and a `@State` flag there
    /// would tear Settings down mid-interaction the moment the user flips the
    /// Production/Test picker inside it.
    var showSettings = false

    // Persisted-settings store plus the sync / realtime / retry machinery.
    // These are module-`internal` (not `private`) only so the sync orchestration
    // can live in `AppModel+Sync.swift` while remaining owned by `AppModel`;
    // `@ObservationIgnored` keeps them off the observation graph. Treat as
    // private to the type — nothing outside `AppModel` should touch them.
    let defaults: UserDefaults
    @ObservationIgnored var supabaseClient: SupabaseClient?
    @ObservationIgnored var authStorage: EarnlineAuthStorage?
    @ObservationIgnored var queuedSyncTask: Task<Void, Never>?
    @ObservationIgnored var realtimeChannel: RealtimeChannelV2?
    /// The client that owns `realtimeChannel` — kept so teardown can remove the
    /// channel even after `supabaseClient` has been reset to nil.
    @ObservationIgnored var realtimeClient: SupabaseClient?
    @ObservationIgnored var realtimeTask: Task<Void, Never>?
    @ObservationIgnored var realtimeContext: ModelContext?
    @ObservationIgnored var configRefreshTask: Task<Void, Never>?
    @ObservationIgnored var followUpSyncRequested = false
    /// Bumped on every workspace detach. An in-flight `syncNow` snapshots the
    /// generation before its await and discards its results if the workspace
    /// changed underneath it — otherwise a Production pass finishing after a
    /// switch to Test would write its cursor under Test's keys.
    @ObservationIgnored var syncGeneration = 0
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored var retryAttempt = 0
    @ObservationIgnored var invokedByRetry = false
    @ObservationIgnored var lastSyncFailed = false
    @ObservationIgnored var profileNeedsSync = false
    @ObservationIgnored var profileEditGeneration = 0
    @ObservationIgnored var isApplyingRemoteProfile = false
    @ObservationIgnored let pathMonitor = NWPathMonitor()
    @ObservationIgnored var pathMonitorStarted = false
    @ObservationIgnored var pathWasSatisfied = true
    @ObservationIgnored private var lockWindow: UIWindow?
    @ObservationIgnored private var isUnlocking = false

    // swiftlint:disable:next function_body_length
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateWorkspaceCurrencyProfilesIfNeeded(defaults: defaults)

        let savedEnvironment = defaults.string(forKey: "workspaceEnvironment").flatMap(WorkspaceEnvironment.init(rawValue:))
        let resolvedEnvironment = Self.isLocalOnlyDevBuild ? .test : (savedEnvironment ?? .production)
        let resolvedBaseCurrencyCode = Self.normalizedCurrencyCode(
            defaults.string(forKey: Self.workspaceDefaultKey("baseCurrencyCode", environment: resolvedEnvironment)),
            fallback: Self.defaultBaseCurrencyCode
        )
        baseCurrencyCode = resolvedBaseCurrencyCode
        let savedSecondary = Self.normalizedCurrencyCode(
            defaults.string(forKey: Self.workspaceDefaultKey("secondaryCurrencyCode", environment: resolvedEnvironment)),
            fallback: Self.defaultSecondaryCurrencyCode
        )
        secondaryCurrencyCode = savedSecondary == resolvedBaseCurrencyCode
            ? Self.replacementCurrencyCode(excluding: resolvedBaseCurrencyCode)
            : savedSecondary
        let rateKey = Self.workspaceDefaultKey("rate", environment: resolvedEnvironment)
        let r = defaults.object(forKey: rateKey) == nil
            ? Self.defaultExchangeRate
            : defaults.double(forKey: rateKey)
        rate = Self.validExchangeRate(r, fallback: Self.defaultExchangeRate)
        // Supabase config is per environment: seed each field from its stored
        // per-workspace value, falling back to the project preloaded for that
        // environment so the app syncs out of the box with nothing to paste.
        let config = resolvedEnvironment.defaultSupabaseConfig
        supabaseURLString = Self.configuredSupabaseValue(
            defaults.string(forKey: "supabaseURLString.\(resolvedEnvironment.rawValue)"),
            fallback: config.url
        )
        supabaseKey = Self.configuredSupabaseValue(
            defaults.string(forKey: "supabaseKey.\(resolvedEnvironment.rawValue)"),
            fallback: config.publishableKey
        )
        let resolvedWorkspaceID = defaults.string(forKey: "workspaceID.\(resolvedEnvironment.rawValue)")
            ?? defaults.string(forKey: "workspaceID")
            ?? resolvedEnvironment.workspaceID
        let resolvedStoreMode: AccountStoreMode = defaults.bool(forKey: "accountStoreMigrated.\(resolvedWorkspaceID)")
            ? .account
            : .legacy
        workspaceEnvironment = resolvedEnvironment
        workspaceID = resolvedWorkspaceID
        accountStoreMode = resolvedStoreMode
        workspaceStoreIdentity = "\(resolvedEnvironment.rawValue):\(resolvedWorkspaceID):\(resolvedStoreMode.rawValue)"
        defaults.set(resolvedEnvironment.rawValue, forKey: "workspaceEnvironment")
        defaults.set(resolvedWorkspaceID, forKey: "workspaceID")
        defaults.set(resolvedWorkspaceID, forKey: "workspaceID.\(resolvedEnvironment.rawValue)")
        profileNeedsSync = defaults.bool(forKey: "profileNeedsSync.\(resolvedEnvironment.rawValue)")
        let onboardingCompletedKey = Self.onboardingDefaultKey(
            "onboardingCompleted",
            environment: resolvedEnvironment,
            workspaceID: resolvedWorkspaceID
        )
        let legacyOnboardingKey = Self.workspaceDefaultKey(
            "onboardingCompleted",
            environment: resolvedEnvironment
        )
        if defaults.object(forKey: onboardingCompletedKey) == nil,
           defaults.object(forKey: legacyOnboardingKey) != nil {
            defaults.set(defaults.bool(forKey: legacyOnboardingKey), forKey: onboardingCompletedKey)
        }
        onboardingCompleted = defaults.bool(forKey: onboardingCompletedKey)
        let checkpointStepKey = Self.onboardingDefaultKey(
            "onboardingCheckpointStep",
            environment: resolvedEnvironment,
            workspaceID: resolvedWorkspaceID
        )
        onboardingCheckpointStep = OnboardingCheckpointStep(
            rawValue: defaults.integer(forKey: checkpointStepKey)
        ) ?? .client
        onboardingClientID = defaults.string(
            forKey: Self.onboardingDefaultKey(
                "onboardingClientID",
                environment: resolvedEnvironment,
                workspaceID: resolvedWorkspaceID
            )
        ).flatMap(UUID.init(uuidString:))
        onboardingEntryID = defaults.string(
            forKey: Self.onboardingDefaultKey(
                "onboardingEntryID",
                environment: resolvedEnvironment,
                workspaceID: resolvedWorkspaceID
            )
        ).flatMap(UUID.init(uuidString:))
        let workspaceKeySuffix = resolvedEnvironment.rawValue
        let savedLastSyncAt = defaults.object(forKey: "lastSyncAt.\(workspaceKeySuffix)") as? Date
            ?? defaults.object(forKey: "lastSyncAt") as? Date
        lastSyncAt = savedLastSyncAt
        // Migrate installs from before the cursor/display split and before
        // per-workspace stores: seed the active workspace from the old keys.
        let savedSyncCursor = defaults.object(forKey: "syncCursor.\(workspaceKeySuffix)") as? Date
            ?? defaults.object(forKey: "syncCursor") as? Date
            ?? savedLastSyncAt
        syncCursor = savedSyncCursor
        let storedAppearance: AppearanceMode
        if let saved = defaults.string(forKey: "appearanceMode").flatMap(AppearanceMode.init(rawValue:)) {
            storedAppearance = saved
        } else if let legacyDark = defaults.object(forKey: "prefersDarkMode") as? Bool {
            // Migrate the old binary toggle without changing what the user
            // sees: an explicit choice stays explicit. Fresh installs follow
            // the system, as Apple's own apps do.
            storedAppearance = legacyDark ? .dark : .light
        } else {
            storedAppearance = .system
        }
        #if DEBUG
        if Self.hasUIAutomationLaunchFlag("-uiTestDarkAppearance") {
            // Keep visual regression tests independent from whichever
            // appearance preference the simulator persisted previously.
            // Assigning during initialization does not write the test-only
            // override back to UserDefaults.
            appearanceMode = .dark
        } else {
            appearanceMode = storedAppearance
        }
        #else
        appearanceMode = storedAppearance
        #endif
        accent = Theme.Accent(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .blue
        #if DEBUG
        if Self.hasUIAutomationLaunchFlag("-resetDeveloperMode") {
            defaults.set(false, forKey: "developerModeEnabled")
        }
        if Self.hasUIAutomationLaunchFlag("-demoDeveloperSettings") {
            developerModeEnabled = true
        } else {
            developerModeEnabled = defaults.bool(forKey: "developerModeEnabled")
        }
        if Self.hasUIAutomationLaunchFlag("-resetExperimentalFeatures") {
            defaults.set(false, forKey: "clientBadgesEnabled")
        }
        #else
        developerModeEnabled = defaults.bool(forKey: "developerModeEnabled")
        #endif
        clientBadgesEnabled = defaults.bool(forKey: "clientBadgesEnabled")
        #if DEBUG
        if Self.isRunningUIAutomation && Self.hasUIAutomationLaunchFlag("-demoClientProfile") {
            clientBadgesEnabled = true
        }
        #endif
        requireAppLock = defaults.bool(forKey: "requireAppLock")
        syncMessage = isSupabaseConfigured ? String(localized: "Ready") : String(localized: "Offline")
    }

    // MARK: App lock

    /// Cold launches start covered when the lock is on; the biometric prompt
    /// fires as soon as the window exists (called from the root `.task`).
    func lockOnLaunchIfNeeded() {
        guard canUseAppLock else { return }
        isLocked = true
        showLockWindow()
        attemptUnlockIfNeeded()
    }

    /// Called on backgrounding — covers the content before the app-switcher
    /// snapshot is taken, so amounts never show in the multitasking UI.
    func lockIfNeeded() {
        guard canUseAppLock, !isLocked else { return }
        isLocked = true
        showLockWindow()
    }

    /// Called on `.inactive` — the app-switcher snapshot is taken while the
    /// scene is still inactive, before `.background` fires, so waiting for
    /// backgrounding briefly exposed the ledger in the multitasking UI. This
    /// shows the cover *without* committing the lock: swiping away Control
    /// Center or an incoming-call banner returns straight to content, no
    /// re-authentication.
    func coverIfNeeded() {
        guard canUseAppLock, !isLocked else { return }
        showLockWindow()
    }

    /// Called on `.active` — removes an uncommitted privacy cover. A real
    /// lock (set on `.background`) stays up until `attemptUnlockIfNeeded`
    /// succeeds.
    func uncoverIfNeeded() {
        guard !isLocked else { return }
        hideLockWindow()
    }

    /// Called on activation and by the lock screen's Unlock button.
    func attemptUnlockIfNeeded() {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch await AppLockAuth.evaluate(reason: String(localized: "Unlock your income ledger")) {
            case .authenticated:
                self.isLocked = false
                self.hideLockWindow()
            case .unavailable:
                self.disableUnavailableAppLock()
                self.isLocked = false
                self.hideLockWindow()
            case .denied:
                break
            }
            self.isUnlocking = false
        }
    }

    private var canUseAppLock: Bool {
        guard requireAppLock else { return false }
        guard AppLockAuth.isAuthenticationAvailable else {
            disableUnavailableAppLock()
            return false
        }
        return true
    }

    private func disableUnavailableAppLock() {
        guard requireAppLock else { return }
        requireAppLock = false
        appLockNotice = String(localized: "App Lock was turned off because this iPhone no longer has a device passcode.")
    }

    /// The lock lives in its own alert-level window for the same reason dark
    /// mode is a window-level override: a SwiftUI overlay in the root view
    /// sits *under* presented sheets, and the lock must cover those too.
    private func showLockWindow() {
        guard !Self.isRunningUnitTests else { return }
        guard lockWindow == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = appearanceMode.uiStyle
        window.rootViewController = UIHostingController(
            rootView: LockScreenView { [weak self] in self?.attemptUnlockIfNeeded() }
        )
        window.makeKeyAndVisible()
        lockWindow = window
    }

    private func hideLockWindow() {
        guard let window = lockWindow else { return }
        // Tear the alert-level window down in UIKit's expected order. Leaving
        // its hosting controller attached while dropping the last window
        // reference produced unbalanced appearance transitions in tests and
        // could leave the main scene without a key window after unlock.
        window.resignKey()
        window.isHidden = true
        window.rootViewController = nil
        lockWindow = nil
    }

    // MARK: Undo delete

    /// The last delete, held for a short window so the toast can reverse it.
    var undoableDelete: UndoableDelete?
    @ObservationIgnored private var undoExpiryTask: Task<Void, Never>?

    /// Call after the delete has actually saved — a toast for a delete that
    /// failed to persist would offer to undo nothing.
    func stageUndo(_ delete: UndoableDelete) {
        undoableDelete = delete
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undoableDelete = nil
        }
    }

    /// Returns `nil` on success or the failure message — surface it with
    /// `.saveErrorAlert` so a failed restore never passes for a successful one.
    @discardableResult
    func performUndo(context: ModelContext) -> String? {
        guard let undoableDelete else { return nil }
        undoExpiryTask?.cancel()
        self.undoableDelete = nil
        do {
            try undoableDelete.restore(in: context)
            try context.save()
            ledgerDataRevision &+= 1
            queueSync(context: context)
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    // MARK: Appearance

    /// Pushes the appearance choice onto every window of every scene.
    /// `preferredColorScheme` only styles the presentation it's declared in, so
    /// sheets (Search, Insights, Pending, Settings), alerts, and menus kept
    /// following the *system* appearance — the toggle looked broken whenever
    /// the system scheme disagreed. A window-level override covers them all;
    /// `.system` clears the override (`.unspecified`) so the device scheme
    /// flows through untouched.
    func applyAppearance() {
        let style = appearanceMode.uiStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    // MARK: Currency

    /// A value-type snapshot of the current currency settings. The money math
    /// lives in `CurrencyConverter` so it's testable without an `AppModel`;
    /// rebuilt per read since the three fields are trivial to copy.
    var converter: CurrencyConverter {
        CurrencyConverter(baseCurrencyCode: baseCurrencyCode,
                          secondaryCurrencyCode: secondaryCurrencyCode,
                          rate: rate)
    }

    func conversionRate(from code: String) -> Decimal? { converter.conversionRate(from: code) }
    func canConvert(_ code: String) -> Bool { converter.canConvert(code) }
    func toBase(_ amount: Decimal, code: String) -> Decimal { converter.toBase(amount, code: code) }
    func secondary(_ base: Decimal) -> Decimal { converter.secondary(base) }
    func primaryString(_ base: Decimal) -> String { converter.primaryString(base) }
    func secondaryString(_ base: Decimal) -> String { converter.secondaryString(base) }

    // MARK: Grouping, totals & insights

    /// The aggregation layer — grouping/totals, the daily heatmap, and the
    /// pending queue — lives in the pure `Insights` value type, built from the
    /// current `converter` so the math stays unit-testable in isolation.
    ///
    /// Callers use `app.insights.…` directly. There used to be a forwarder here
    /// for each method; every one of them had lost its last production caller
    /// when `LedgerSnapshot` and `InsightsDashboardSnapshot` replaced the
    /// per-client-per-month API, leaving a dozen dead methods on the app's
    /// central observable object that read as live paths.
    var insights: Insights { Insights(converter: converter) }

    /// Rebuild local hold-until reminders from the current entries. Called after
    /// every save point (via `queueSync`) and after a sync pull, so the schedule
    /// always matches the data without any delta tracking. Stateful (fetches the
    /// context), so it stays on `AppModel` rather than in `Insights`.
    func refreshPendingReminders(context: ModelContext) {
        // Reminders only ever exist for in-progress lines with a hold date
        // (`PendingNotifications.desiredRequests` drops everything else), so
        // fetch just those instead of materializing the whole table after
        // every save. Legacy raw statuses all map to `.paid`, so matching the
        // raw column against `.inProgress` is exact.
        let inProgress = EntryStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.holdUntil != nil && $0.statusRaw == inProgress }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        PendingNotifications.sync(entries)
    }

    static func workspaceDefaultKey(_ key: String, environment: WorkspaceEnvironment) -> String {
        "\(key).\(environment.rawValue)"
    }

    static func onboardingDefaultKey(
        _ key: String,
        environment: WorkspaceEnvironment,
        workspaceID: String
    ) -> String {
        "\(key).\(environment.rawValue).\(workspaceID)"
    }

    func onboardingDefaultKey(_ key: String) -> String {
        Self.onboardingDefaultKey(key, environment: workspaceEnvironment, workspaceID: workspaceID)
    }

    /// Reloads the checkpoint whenever account resolution changes the active
    /// workspace without changing the Production/Test environment.
    func loadOnboardingState(migrateLegacyFlag: Bool = false) {
        let completedKey = onboardingDefaultKey("onboardingCompleted")
        if migrateLegacyFlag,
           defaults.object(forKey: completedKey) == nil {
            let legacyKey = workspaceDefaultKey("onboardingCompleted")
            if defaults.object(forKey: legacyKey) != nil {
                defaults.set(defaults.bool(forKey: legacyKey), forKey: completedKey)
            }
        }
        onboardingCompleted = defaults.bool(forKey: completedKey)
        onboardingCheckpointStep = OnboardingCheckpointStep(
            rawValue: defaults.integer(forKey: onboardingDefaultKey("onboardingCheckpointStep"))
        ) ?? .client
        onboardingClientID = defaults.string(
            forKey: onboardingDefaultKey("onboardingClientID")
        ).flatMap(UUID.init(uuidString:))
        onboardingEntryID = defaults.string(
            forKey: onboardingDefaultKey("onboardingEntryID")
        ).flatMap(UUID.init(uuidString:))
        isPresentingOnboarding = false
    }

    func startOnboardingReplay() {
        clearOnboardingCheckpoint()
        isPresentingOnboarding = true
    }

    func resetOnboardingForNextLaunch() {
        onboardingCompleted = false
        clearOnboardingCheckpoint()
        isPresentingOnboarding = false
    }

    func stageOnboardingClient(_ clientID: UUID) {
        onboardingClientID = clientID
        onboardingEntryID = nil
        onboardingCheckpointStep = .income
    }

    func stageOnboardingEntry(_ entryID: UUID) {
        onboardingEntryID = entryID
        onboardingCheckpointStep = .done
    }

    func completeOnboarding() {
        onboardingCompleted = true
        clearOnboardingCheckpoint()
        isPresentingOnboarding = false
    }

    /// Decides whether first-run UI is safe to show only after local cleanup
    /// and the initial remote pull. Existing ledger data wins over a missing
    /// local flag, preventing upgraded users and newly paired devices from
    /// creating duplicate clients.
    @discardableResult
    func resolveOnboardingPresentation(
        context: ModelContext,
        remoteStateKnown: Bool
    ) throws -> Bool {
        guard !onboardingCompleted else {
            isPresentingOnboarding = false
            return false
        }

        if let checkpointClientID = onboardingClientID {
            var checkpoint = FetchDescriptor<Client>(
                predicate: #Predicate { $0.id == checkpointClientID }
            )
            checkpoint.fetchLimit = 1
            if try !context.fetch(checkpoint).isEmpty {
                isPresentingOnboarding = true
                return true
            }
            clearOnboardingCheckpoint()
        }

        var clients = FetchDescriptor<Client>()
        clients.fetchLimit = 1
        var entries = FetchDescriptor<Entry>()
        entries.fetchLimit = 1
        if try !context.fetch(clients).isEmpty || !context.fetch(entries).isEmpty {
            completeOnboarding()
            return false
        }

        guard remoteStateKnown else {
            isPresentingOnboarding = false
            return false
        }
        isPresentingOnboarding = true
        return true
    }

    private func clearOnboardingCheckpoint() {
        onboardingCheckpointStep = .client
        onboardingClientID = nil
        onboardingEntryID = nil
    }

    private func persist(_ id: UUID?, forKey key: String) {
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Currency settings used to share three global UserDefaults keys across
    /// Production and Test. Migrate the last cached tuple to Production only,
    /// then force the first pass for both environments to read the authoritative
    /// cloud profile instead of pushing a potentially cross-contaminated cache.
    private static func migrateWorkspaceCurrencyProfilesIfNeeded(defaults: UserDefaults) {
        let migrationKey = "workspaceCurrencyProfileStorageVersion"
        guard defaults.integer(forKey: migrationKey) < workspaceCurrencyProfileStorageVersion else { return }

        let production = WorkspaceEnvironment.production
        let productionBaseKey = workspaceDefaultKey("baseCurrencyCode", environment: production)
        let productionSecondaryKey = workspaceDefaultKey("secondaryCurrencyCode", environment: production)
        let productionRateKey = workspaceDefaultKey("rate", environment: production)

        if defaults.object(forKey: productionBaseKey) == nil,
           let legacyBase = defaults.string(forKey: "baseCurrencyCode") {
            defaults.set(legacyBase, forKey: productionBaseKey)
        }
        if defaults.object(forKey: productionSecondaryKey) == nil,
           let legacySecondary = defaults.string(forKey: "secondaryCurrencyCode") {
            defaults.set(legacySecondary, forKey: productionSecondaryKey)
        }
        if defaults.object(forKey: productionRateKey) == nil,
           defaults.object(forKey: "rate") != nil {
            defaults.set(defaults.double(forKey: "rate"), forKey: productionRateKey)
        }

        for environment in WorkspaceEnvironment.allCases {
            defaults.set(false, forKey: workspaceDefaultKey("profileNeedsSync", environment: environment))
        }
        defaults.set(workspaceCurrencyProfileStorageVersion, forKey: migrationKey)
    }

    nonisolated static func validExchangeRate(_ value: Double, fallback: Double = defaultExchangeRate) -> Double {
        if value.isFinite, value > 0 {
            return value
        }
        if fallback.isFinite, fallback > 0 {
            return fallback
        }
        return defaultExchangeRate
    }

    nonisolated static func normalizedCurrencyCode(_ code: String?, fallback: String) -> String {
        let normalized = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if supportedCurrencyCodes.contains(normalized) {
            return normalized
        }
        return supportedCurrencyCodes.contains(fallback) ? fallback : defaultBaseCurrencyCode
    }

    nonisolated static func replacementCurrencyCode(excluding code: String) -> String {
        supportedCurrencyCodes.first { $0 != code } ?? defaultSecondaryCurrencyCode
    }
}

extension Decimal {
    func rounded(_ scale: Int = 0) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
