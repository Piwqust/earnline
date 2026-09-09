import SwiftUI
import SwiftData

/// Settings as a native inset-grouped `Form` — the system owns row heights,
/// hairlines, section headers/footers, Dynamic Type, and RTL mirroring, the
/// way Apple's own Settings-style screens do. Interactive rows lead with a
/// bare 17 pt monochrome glyph (`SettingsRowLabel` — the same icon idiom as
/// `ChromeRow` and the ledger menus); read-only value rows stay iconless like
/// Apple's About screens. Nothing here renders in the accent: action rows are
/// calm ink-on-white rows, and the accent stays reserved for status and
/// totals elsewhere in the app.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var saveError: String?
    @State private var diagnosticsError: String?
    /// Counts shown in the form, refreshed on demand via `fetchCount` (a SQL
    /// COUNT). The previous live `@Query`s materialized every synced row and
    /// re-filtered them on each keystroke/pick, which made the
    /// currency pickers visibly lag on a large ledger.
    @State private var pendingSyncCount = 0
    @State private var unsupportedCurrencyCount = 0
    @State private var isFetchingRate = false
    @State private var rateFetchFailed = false
    @State private var rateFetchNote: String?
    /// The rate field edits this draft, not `appModel.rate`. Binding the field
    /// straight to the model published every keystroke through the observation
    /// graph — the whole ledger re-derived its rows and every money label
    /// reformatted per character, which made typing here visibly lag on a
    /// large ledger. `nil` means "not editing": the field shows the model.
    @State private var currencyDraft: CurrencyProfileDraft?
    @State private var rateRequest: Task<Void, Never>?
    @State private var rateEditGeneration = 0
    @State private var pendingSyncRecoveryAction: SyncRecoveryAction?
    @State private var isResettingLocalData = false
    @State private var stressSeedNote: String?
    @State private var showingPairingCode = false
    /// On-device (guest) ledger available to import into the signed-in account.
    /// Loaded once on appear; `nil` until then, empty when there is nothing to
    /// bring over. Backs the "Import on-device ledger" action.
    @State private var guestLedger: GuestLedgerMigration.Summary?
    @State private var isImportingGuestLedger = false
    @State private var pendingGuestImport = false
    @State private var guestImportNote: String?
    #if DEBUGMENU
    @State private var showingDebugMenu = false
    #endif
    @State private var csvTransferRoute: CSVTransferRoute?
    @State private var backupTransferRoute: LedgerBackupTransferRoute?
    private let currencies = AppModel.supportedCurrencyCodes

    var body: some View {
        @Bindable var app = appModel
        Form {
            if app.workspaceEnvironment == .production,
               app.isAccountReady,
               app.accountSession?.isLocalOnly != true {
                AccountDevicesSection(showingPairingCode: $showingPairingCode)
            }

            if app.isSupabaseConfigured, let guestLedger, !guestLedger.isEmpty {
                Section {
                    Button {
                        pendingGuestImport = true
                    } label: {
                        HStack {
                            SettingsRowLabel("Import on-device ledger",
                                             glyph: "square.and.arrow.down.on.square")
                            Spacer()
                            if isImportingGuestLedger { ProgressView() }
                        }
                    }
                    .disabled(isImportingGuestLedger)
                    .accessibilityIdentifier("settings.importGuestLedger")
                } header: {
                    Text("On-device ledger")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        // swiftlint:disable:next line_length
                        Text("Bring the \(guestLedgerCountText) you saved with “Continue without an account” into this account and sync them. The on-device copy stays on this device.")
                        if let guestImportNote {
                            Label(guestImportNote, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                SyncSettingsContent(
                    pendingSyncCount: pendingSyncCount,
                    isResettingLocalData: isResettingLocalData,
                    onUseCloudCopy: { pendingSyncRecoveryAction = .useCloudCopy }
                )
            } header: {
                Text("Sync")
            } footer: {
                if let syncError = app.syncError, !syncError.isEmpty {
                    Text(syncError).foregroundStyle(Theme.statusCanceled)
                }
            }

            Section("Appearance") {
                Picker(selection: $app.appearanceMode) {
                    ForEach(AppModel.AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowLabel("Appearance", glyph: "sun.max")
                }
                .tint(valueGray)
                LabeledContent {
                    accentMenu(selection: $app.accent)
                } label: {
                    SettingsRowLabel("Accent color", glyph: "drop")
                }
            }

            Section {
                NavigationLink {
                    ProjectIconsSettingsView()
                } label: {
                    SettingsRowLabel("Project icons", glyph: "folder")
                }
                .accessibilityIdentifier("settings.projectIcons")
            } header: {
                Text("Projects")
            } footer: {
                Text("Choose one quiet marker for each project. It appears beside the project name in your ledger.")
            }

            Section {
                // Flipping either way demands the owner's face/passcode —
                // otherwise anyone holding the phone could switch it off.
                Toggle(isOn: Binding(
                    get: { appModel.requireAppLock },
                    set: { setAppLock($0) }
                )) {
                    SettingsRowLabel(verbatim: AppLockAuth.settingTitle, glyph: "faceid")
                }
                if let privacyPolicyURL = PrivacyPolicyURL.current {
                    Link(destination: privacyPolicyURL) {
                        SettingsRowLabel("Privacy policy", glyph: "hand.raised")
                    }
                    .accessibilityIdentifier("settings.privacyPolicy")
                }
            } header: {
                Text("Privacy")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Locks the ledger when the app goes to the background. Unlock with biometrics or your passcode.")
                    if let notice = appModel.appLockNotice {
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.statusProgress)
                            .accessibilityIdentifier("settings.appLockNotice")
                    }
                    if let notice = appModel.accountSecurityNotice {
                        Label(notice, systemImage: "exclamationmark.shield.fill")
                            .foregroundStyle(Theme.statusProgress)
                            .accessibilityIdentifier("settings.accountSecurityNotice")
                    }
                }
            }

            Section {
                currencyPicker("Primary",
                               selection: currencyBinding(isBase: true), options: currencies)
                currencyPicker("Secondary",
                               selection: currencyBinding(isBase: false),
                               options: currencies.filter { $0 != editedCurrency.base })
            } header: {
                Text("Currency")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if unsupportedCurrencyCount > 0 {
                        Label("\(unsupportedCurrencyCount) line(s) in an unsupported currency are excluded from consolidated totals.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.statusProgress)
                    }
                    // swiftlint:disable:next line_length
                    Text("Amounts stay in their original currency. Only the primary and secondary currencies are converted for consolidated totals.")
                }
            }

            ConversionRateSettingsSection(
                baseCurrencyCode: editedCurrency.base,
                secondaryCurrencyCode: editedCurrency.secondary,
                secondaryExample: editedCurrency.rate.map {
                    CurrencyFormatter.string(Decimal($0 * 100), code: editedCurrency.secondary)
                } ?? "—",
                rate: rateFieldBinding,
                isFetchingRate: isFetchingRate,
                rateFetchFailed: rateFetchFailed,
                rateFetchNote: rateFetchNote,
                onCommitRate: {},
                onFetchRate: fetchRate
            )

            if currencyDraft != nil {
                Section {
                    Button("Apply currencies and rate", action: commitRateDraft)
                        .disabled(!editedCurrency.isValid)
                        .accessibilityIdentifier("settings.currency.apply")
                    Button("Cancel currency changes") { discardCurrencyDraft() }
                } footer: {
                    Text("Enter or fetch a rate for this pair, then apply. Totals keep using the previous settings until then.")
                }
            }

            Section("About") {
                aboutContent
            }

            #if DEBUGMENU
            Section {
                Button {
                    showingDebugMenu = true
                } label: {
                    SettingsRowLabel("Debug menu", glyph: "ladybug")
                }
                .accessibilityIdentifier("settings.debugMenu")
            } footer: {
                Text(verbatim: "Dev build only — this section does not exist in the App Store version.")
            }
            #endif

            Section {
                Toggle(isOn: $app.developerModeEnabled) {
                    SettingsRowLabel("Developer Mode", glyph: "wrench.and.screwdriver")
                }
                .accessibilityIdentifier("settings.developerMode")
            } footer: {
                Text("Sync controls, workspace diagnostics, and data-recovery tools stay out of the everyday settings path.")
            }

            if app.developerModeEnabled {
                Section {
                    Toggle(isOn: $app.clientBadgesEnabled) {
                        SettingsRowLabel("Client badges", glyph: "medal")
                    }
                    .accessibilityIdentifier("settings.clientBadges")

                    // Replays the real first-run flow over the ledger. Settings
                    // closes first so the layer is not trapped behind this
                    // sheet. It creates a real client and a real line, exactly
                    // as it does on a fresh install.
                    Button {
                        app.showSettings = false
                        app.startOnboardingReplay()
                    } label: {
                        SettingsRowLabel("Onboarding", glyph: "sparkles.rectangle.stack")
                    }
                    .accessibilityIdentifier("settings.onboarding")
                } header: {
                    Text("Experimental")
                } footer: {
                    // swiftlint:disable:next line_length
                    Text("Experimental features may change or be removed in a future version. Onboarding replays the two-step introduction; finishing it adds the client you name and the first line you write.")
                }

                #if DEBUG
                Section {
                    // Production and Test are two separate Supabase projects
                    // with their own stores, currency profiles, and workspace
                    // IDs. `workspaceEnvironment.didSet` owns the switch; this
                    // row is the only way to reach it, so it belongs beside the
                    // connection it selects.
                    Picker(selection: $app.workspaceEnvironment) {
                        ForEach(AppModel.WorkspaceEnvironment.allCases) { environment in
                            Text(environment.title).tag(environment)
                        }
                    } label: {
                        SettingsRowLabel("Workspace", glyph: "externaldrive")
                    }
                    .pickerStyle(.menu)
                    .tint(valueGray)
                    .accessibilityIdentifier("settings.workspace")

                    NavigationLink {
                        SupabaseConnectionSettingsView()
                    } label: {
                        HStack {
                            SettingsRowLabel("Personal Supabase database", glyph: "cylinder.split.1x2")
                            Spacer()
                            Text(app.isUsingCustomSupabaseConnection ? "Personal" : "Built-in")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.supabaseConnection")
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Connect a Supabase project you administer only when you intentionally need a separate database.")
                }
                #endif

                #if DEBUG
                Section {
                    DeveloperDataSettingsContent(
                        workspaceDisplayName: app.workspaceDisplayName,
                        isResettingLocalData: isResettingLocalData,
                        isSyncing: app.isSyncing,
                        onResetAndPull: { pendingSyncRecoveryAction = .reloadCurrent },
                        onImportSample: importSampleLedger,
                        onSeedStressData: seedStressDataset
                    )
                } header: {
                    Text("Data")
                } footer: {
                    if let stressSeedNote {
                        Text(stressSeedNote)
                    }
                }
                #endif

            }

            Section {
                Button {
                    csvTransferRoute = .exportLedger
                } label: {
                    SettingsRowLabel("Export CSV", glyph: "square.and.arrow.up")
                }
                Button {
                    csvTransferRoute = .importLedger
                } label: {
                    SettingsRowLabel("Import CSV", glyph: "square.and.arrow.down")
                }
                Button {
                    backupTransferRoute = .export
                } label: {
                    SettingsRowLabel("Export full backup", glyph: "externaldrive.badge.plus")
                }
                Button {
                    backupTransferRoute = .import
                } label: {
                    SettingsRowLabel("Import full backup", glyph: "externaldrive.badge.arrow.down")
                }
                NavigationLink {
                    SafetySnapshotsView()
                } label: {
                    SettingsRowLabel("Safety snapshots", glyph: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("settings.safetySnapshots.open")
            } header: {
                Text("Data")
            } footer: {
                // swiftlint:disable:next line_length
                Text("CSV is for exchanging income lines. The full JSON backup also includes notes, project icons, month reviews, and settings; it is merge-only and does not replay sync deletes. Safety snapshots are written automatically before the local ledger is emptied.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .sheetHeader("Settings", onClose: { dismiss() })
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .sheet(isPresented: $showingPairingCode) {
            PairingCodeDisplaySheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUGMENU
        .sheet(isPresented: $showingDebugMenu) {
            DebugMenuView()
        }
        #endif
        .task {
            refreshCounts()
            refreshGuestLedger()
        }
        // The sheet outlives a workspace switch (it's presented by the host),
        // so re-read the counts from whatever store is now underneath.
        .onChange(of: appModel.workspaceEnvironment) {
            discardCurrencyDraft()
            rateFetchNote = nil
            refreshCounts()
        }
        .onChange(of: appModel.workspaceStoreIdentity) { discardCurrencyDraft() }
        .onDisappear { rateRequest?.cancel() }
        .onChange(of: appModel.baseCurrencyCode) { refreshCounts(); rateFetchNote = nil }
        .onChange(of: appModel.secondaryCurrencyCode) { refreshCounts(); rateFetchNote = nil }
        .onChange(of: appModel.isSyncing) { _, syncing in
            if !syncing { refreshCounts() }
        }
        .confirmationDialog(syncRecoveryConfirmationTitle,
                            isPresented: syncRecoveryConfirmationBinding,
                            titleVisibility: .visible) {
            Button(syncRecoveryConfirmationButtonTitle, role: .destructive) {
                let action = pendingSyncRecoveryAction
                pendingSyncRecoveryAction = nil
                runSyncRecoveryAction(action)
            }
            Button("Cancel", role: .cancel) { pendingSyncRecoveryAction = nil }
        } message: {
            Text(syncRecoveryConfirmationMessage)
        }
        .confirmationDialog("Import your on-device ledger?",
                            isPresented: $pendingGuestImport,
                            titleVisibility: .visible) {
            Button("Import and sync") { importGuestLedger() }
            Button("Cancel", role: .cancel) {}
        } message: {
            // swiftlint:disable:next line_length
            Text("The \(guestLedgerCountText) you saved with “Continue without an account” will be added to this account and synced. Your on-device copy is left untouched, and importing again won’t create duplicates.")
        }
        .saveErrorAlert($saveError)
        .saveErrorAlert($diagnosticsError, title: "Could not load sync status")
        .sheet(item: $csvTransferRoute) { route in
            CSVTransferView(route: route)
        }
        .sheet(item: $backupTransferRoute) { route in
            LedgerBackupTransferView(route: route)
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private var aboutContent: some View {
        valueRow("Version", value: appVersion)
            .accessibilityIdentifier("settings.version")
        NavigationLink {
            ChangelogView()
        } label: {
            SettingsRowLabel("What's new", glyph: "sparkles")
        }
        .accessibilityIdentifier("settings.whatsNew")
    }

    /// Read-only row: title in ink, value trailing in gray — the system
    /// "App language · English" row shape via `LabeledContent`.
    private func valueRow(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Currency picker as a native menu picker — the system carries the
    /// checkmark, chevrons, and the Liquid Glass menu panel. The value reads
    /// as the currency's own symbol *character* ("$ USD", "₽ RUB") rather
    /// than an SF Symbol glyph, so the trailing text is one consistent
    /// typographic unit.
    private func currencyPicker(_ title: LocalizedStringKey,
                                selection: Binding<String>,
                                options: [String]) -> some View {
        Picker(selection: selection) {
            ForEach(options, id: \.self) { code in
                Text(verbatim: "\(CurrencyFormatter.symbol(for: code)) \(code)").tag(code)
            }
        } label: {
            Text(title)
        }
        .pickerStyle(.menu)
        .tint(valueGray)
    }

    /// Settings picker values use the standard secondary-label gray while the
    /// controls themselves remain native Pickers with the system popup and
    /// selection behavior.
    private var valueGray: Color { Theme.secondaryLabel }

    /// Accent picker — ChatGPT's "Accent color" row: the collapsed value is a
    /// colored dot + name; the menu rows keep their original-color dots (via
    /// `Theme.Accent.dotImage`) with the system checkmark on the selection.
    private func accentMenu(selection: Binding<Theme.Accent>) -> some View {
        Menu {
            Picker("Accent color", selection: selection) {
                ForEach(Theme.Accent.allCases) { choice in
                    Label {
                        Text(choice.title)
                    } icon: {
                        Image(uiImage: choice.dotImage)
                    }
                    .tag(choice)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(selection.wrappedValue.color)
                    .frame(width: 10, height: 10)
                Text(selection.wrappedValue.title)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accent color")
        .accessibilityValue(selection.wrappedValue.title)
    }

    private var syncRecoveryConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingSyncRecoveryAction != nil },
            set: { if !$0 { pendingSyncRecoveryAction = nil } }
        )
    }

    private var syncRecoveryConfirmationTitle: String {
        switch pendingSyncRecoveryAction {
        case .reloadCurrent:
            return String(localized: "Reload this workspace?")
        case .useCloudCopy:
            return String(localized: "Use the cloud copy?")
        case nil:
            return ""
        }
    }

    private var syncRecoveryConfirmationButtonTitle: String {
        switch pendingSyncRecoveryAction {
        case .reloadCurrent:
            return String(localized: "Reset and pull")
        case .useCloudCopy:
            return String(localized: "Use cloud copy")
        case nil:
            return String(localized: "Continue")
        }
    }

    private var syncRecoveryConfirmationMessage: String {
        switch pendingSyncRecoveryAction {
        case .useCloudCopy:
            // swiftlint:disable:next line_length
            return String(localized: "Unsynced changes on this iPhone will be discarded and replaced by the cloud copy. Remote rows are not deleted.")
        case .reloadCurrent, nil:
            // swiftlint:disable:next line_length
            return String(localized: "Only the selected local store on this iPhone will be removed. Supabase rows and the other workspace store will not be deleted.")
        }
    }

    /// Marketing version from the bundle (Info.plist `CFBundleShortVersionString`),
    /// so the About row never drifts from the shipped build.
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func refreshCounts() {
        let base = appModel.baseCurrencyCode
        let secondary = appModel.secondaryCurrencyCode
        let synced = SyncState.synced.rawValue
        let unsupported = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.currencyCode != base && $0.currencyCode != secondary }
        )
        // Match `SyncCoordinator.pushLocalRows`: SQL `NULL != 'synced'` is not
        // true, so a never-stamped row would otherwise vanish from this count
        // while still being pushed on the next pass.
        let dirtyClients = FetchDescriptor<Client>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }
        )
        let dirtyEntries = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }
        )
        let dirtyHeadings = FetchDescriptor<Heading>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }
        )
        let dirtyProjectIcons = FetchDescriptor<ProjectIconPreference>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }
        )
        let dirtyMonthReviews = FetchDescriptor<MonthReview>(
            predicate: #Predicate { $0.syncStateRaw == nil || $0.syncStateRaw != synced }
        )
        let tombstones = FetchDescriptor<SyncTombstone>()
        do {
            let unsupportedCount = try context.fetchCount(unsupported)
            let pendingClients = try context.fetchCount(dirtyClients)
            let pendingEntries = try context.fetchCount(dirtyEntries)
            let pendingHeadings = try context.fetchCount(dirtyHeadings)
            let pendingProjectIcons = try context.fetchCount(dirtyProjectIcons)
            let pendingMonthReviews = try context.fetchCount(dirtyMonthReviews)
            let pendingTombstones = try context.fetchCount(tombstones)
            let pendingCount = pendingClients + pendingEntries + pendingHeadings
                + pendingProjectIcons + pendingMonthReviews + pendingTombstones
            unsupportedCurrencyCount = unsupportedCount
            pendingSyncCount = pendingCount
            diagnosticsError = nil
        } catch {
            diagnosticsError = String(localized: "Could not read local sync status. Your data was not changed.")
        }
    }

    private func setAppLock(_ enable: Bool) {
        guard enable != appModel.requireAppLock else { return }
        Task { @MainActor in
            switch await AppLockAuth.evaluate(reason: String(localized: "Confirm to change the app lock")) {
            case .authenticated:
                appModel.requireAppLock = enable
                appModel.appLockNotice = nil
            case .unavailable:
                if enable {
                    appModel.appLockNotice = AppLockAuth.unavailableMessage
                }
            case .denied:
                break
            }
        }
    }

    private var editedCurrency: CurrencyProfileDraft {
        currencyDraft ?? CurrencyProfileDraft(base: appModel.baseCurrencyCode,
                                              secondary: appModel.secondaryCurrencyCode,
                                              rate: appModel.rate)
    }

    private func invalidateRateRequest() {
        rateEditGeneration += 1
        rateRequest?.cancel()
        rateRequest = nil
        isFetchingRate = false
        rateFetchNote = nil
    }

    private func discardCurrencyDraft() {
        invalidateRateRequest()
        currencyDraft = nil
    }

    private func currencyBinding(isBase: Bool) -> Binding<String> {
        Binding(
            get: { isBase ? editedCurrency.base : editedCurrency.secondary },
            set: { code in
                invalidateRateRequest()
                var draft = editedCurrency
                if isBase { draft.selectBase(code) } else { draft.selectSecondary(code) }
                currencyDraft = draft
            }
        )
    }

    private var rateFieldBinding: Binding<Double> {
        Binding(
            get: { editedCurrency.rate ?? 0 },
            set: { value in
                invalidateRateRequest()
                var draft = editedCurrency
                draft.rate = value
                currencyDraft = draft
            }
        )
    }

    private func commitRateDraft() {
        guard let draft = currencyDraft, draft.isValid else { return }
        invalidateRateRequest()
        if appModel.applyCurrencyDraft(draft) { currencyDraft = nil }
    }

    private func fetchRate() {
        invalidateRateRequest()
        isFetchingRate = true
        let draft = editedCurrency
        let editGeneration = rateEditGeneration
        let profileGeneration = appModel.profileEditGeneration
        let workspace = appModel.workspaceStoreIdentity
        rateRequest = Task { @MainActor in
            defer {
                if editGeneration == rateEditGeneration { isFetchingRate = false }
            }
            do {
                let fetched = try await ExchangeRateService.fetch(base: draft.base, secondary: draft.secondary)
                guard !Task.isCancelled, editGeneration == rateEditGeneration,
                      profileGeneration == appModel.profileEditGeneration,
                      workspace == appModel.workspaceStoreIdentity, draft == editedCurrency else { return }
                var updated = draft
                updated.rate = fetched
                currencyDraft = updated
                rateFetchFailed = false
                rateFetchNote = String(localized: "Rate loaded. Apply to update totals.")
            } catch {
                guard !Task.isCancelled, editGeneration == rateEditGeneration,
                      workspace == appModel.workspaceStoreIdentity else { return }
                rateFetchFailed = true
                rateFetchNote = error.localizedDescription
            }
        }
    }

    /// DEBUG-only profiling aid: thousands of local-only lines (pre-marked
    /// synced, so nothing ever pushes to a workspace). "Reset and pull"
    /// removes them again.
    private func seedStressDataset() {
        let inserted = SampleData.seedStress(context)
        stressSeedNote = inserted > 0
            ? String(localized: "Inserted \(inserted) local-only stress rows. Reset and pull removes them.")
            : String(localized: "Stress rows already present. Reset and pull removes them.")
        refreshCounts()
    }

    private func importSampleLedger() {
        do {
            let inserted = try IncomeLedgerImporter.importBundledLedger(into: context)
            if inserted > 0 {
                mutations.recordExternalSave()
                appModel.queueSync(context: context)
            }
            refreshCounts()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }

    /// Human-readable size of the on-device (guest) ledger awaiting import.
    private var guestLedgerCountText: String {
        let entries = guestLedger?.entries ?? 0
        if entries == 1 { return String(localized: "1 income line") }
        if entries > 1 { return String(localized: "\(entries) income lines") }
        return String(localized: "income lines")
    }

    /// Load the guest-ledger summary — only when signed into a real syncing
    /// account, so a signed-out or guest session never opens the guest store.
    private func refreshGuestLedger() {
        guard appModel.isSupabaseConfigured else { guestLedger = nil; return }
        do {
            guestLedger = try GuestLedgerMigration.guestLedgerSummary()
        } catch {
            guestLedger = nil
            saveError = String(
                localized: "Could not inspect the on-device ledger. It has not been changed. \(error.localizedDescription)"
            )
        }
    }

    /// Copy the on-device guest ledger into this account and kick a sync. Safe
    /// to run more than once — rows already present are skipped (see
    /// `GuestLedgerMigration`), and the on-device store is never modified.
    private func importGuestLedger() {
        guard !isImportingGuestLedger else { return }
        isImportingGuestLedger = true
        do {
            let summary = try GuestLedgerMigration.importGuestLedgerFromDisk(into: context)
            if summary.total > 0 {
                mutations.recordExternalSave()
                appModel.queueSync(context: context)
                guestImportNote = summary.entries == 1
                    ? String(localized: "Imported 1 line. Syncing to your account.")
                    : String(localized: "Imported \(summary.entries) lines. Syncing to your account.")
            } else {
                guestImportNote = String(localized: "Your on-device ledger is already in this account.")
            }
            refreshGuestLedger()
            refreshCounts()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
        isImportingGuestLedger = false
    }

    private func runSyncRecoveryAction(_ action: SyncRecoveryAction?) {
        guard let action, !isResettingLocalData else { return }
        isResettingLocalData = true
        Task { @MainActor in
            let error: String?
            switch action {
            case .reloadCurrent:
                error = await appModel.resetLocalDataAndPull(context: context)
            case .useCloudCopy:
                error = await appModel.resetLocalDataAndPull(context: context, discardLocalProfile: true)
            }
            refreshCounts()
            isResettingLocalData = false
            if let error, !error.isEmpty {
                saveError = error
            }
        }
    }
}

private enum SyncRecoveryAction {
    case reloadCurrent
    case useCloudCopy
}

/// Shared Settings icon language: precise monochrome symbols with no decorative
/// tile or background. Each symbol is selected for the action it represents.
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    private let title: Text
    private let glyph: String

    init(_ title: LocalizedStringKey, glyph: String) {
        self.title = Text(title)
        self.glyph = glyph
    }

    init(verbatim title: String, glyph: String) {
        self.title = Text(verbatim: title)
        self.glyph = glyph
    }

    init(_ title: Text, glyph: String) {
        self.title = title
        self.glyph = glyph
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowGlyph(glyph: glyph)
            title.foregroundStyle(Theme.label)
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The same monochrome symbol for fields that cannot use `SettingsRowLabel`.
private struct SettingsRowGlyph: View {
    let glyph: String

    var body: some View {
        Image(systemName: glyph)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Theme.label)
            .frame(width: 24)
    }
}
