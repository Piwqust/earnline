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
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var saveError: String?
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
    @State private var rateDraft: Double?
    @FocusState private var rateFieldFocused: Bool
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
                        Text("Bring the \(guestLedgerCountText) you saved with “Continue without an account” into this account and sync them. The on-device copy stays on this device.")
                        if let guestImportNote {
                            Label(guestImportNote, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
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
                NavigationLink {
                    ProjectIconsSettingsView()
                } label: {
                    SettingsRowLabel("Project icons", glyph: "folder")
                }
            } header: {
                Text("Projects")
            } footer: {
                Text("Choose a familiar SF Symbol for every project already used in the ledger.")
            }

            Section {
                currencyPicker("Primary",
                               selection: $app.baseCurrencyCode, options: currencies)
                currencyPicker("Secondary",
                               selection: $app.secondaryCurrencyCode,
                               options: currencies.filter { $0 != app.baseCurrencyCode })
            } header: {
                Text("Currency")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if unsupportedCurrencyCount > 0 {
                        Label("\(unsupportedCurrencyCount) line(s) in an unsupported currency are excluded from consolidated totals.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.statusProgress)
                    }
                    Text("Amounts stay in their original currency. Only the primary and secondary currencies are converted for consolidated totals.")
                }
            }

            conversionRateSection

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
            } footer: {
                Text("Sync controls, workspace diagnostics, and data-recovery tools stay out of the everyday settings path.")
            }

            if app.developerModeEnabled {
                Section {
                    Toggle(isOn: $app.clientBadgesEnabled) {
                        SettingsRowLabel("Client badges", glyph: "medal")
                    }
                    .accessibilityIdentifier("settings.clientBadges")
                } header: {
                    Text("Experimental")
                } footer: {
                    Text("Experimental features may change or be removed in a future version.")
                }

                #if DEBUG
                Section {
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

                Section {
                    developerSyncContent
                } header: {
                    Text("Sync")
                } footer: {
                    if let syncError = app.syncError, !syncError.isEmpty {
                        Text(syncError).foregroundStyle(Theme.statusCanceled)
                    }
                }

                #if DEBUG
                Section {
                    developerDataContent
                } header: {
                    Text("Data")
                } footer: {
                    if let stressSeedNote {
                        Text(stressSeedNote)
                    }
                }
                #endif

                Section("About") {
                    developerAboutContent
                }
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
            } header: {
                Text("Data")
            } footer: {
                Text("Export or import ledger income lines in a standard CSV file. This is not a backup and does not include notes, settings, or sync history.")
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
            rateDraft = nil
            rateFetchNote = nil
            refreshCounts()
        }
        .onChange(of: appModel.baseCurrencyCode) { refreshCounts(); rateFetchNote = nil }
        .onChange(of: appModel.secondaryCurrencyCode) { refreshCounts(); rateFetchNote = nil }
        .onChange(of: appModel.isSyncing) { _, syncing in
            if !syncing { refreshCounts() }
        }
        .onChange(of: appModel.syncConflictCount) { _, count in
            if count > 0 { appModel.developerModeEnabled = true }
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
            Text("The \(guestLedgerCountText) you saved with “Continue without an account” will be added to this account and synced. Your on-device copy is left untouched, and importing again won’t create duplicates.")
        }
        .saveErrorAlert($saveError)
        .sheet(item: $csvTransferRoute) { route in
            CSVTransferView(route: route)
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private var conversionRateSection: some View {
        Section {
            HStack {
                SettingsRowLabel(verbatim: "1 \(appModel.baseCurrencyCode)",
                                 glyph: "chart.line.uptrend.xyaxis")
                Spacer()
                // The decimal pad has no return key, so the draft commits when
                // focus leaves the field or the sheet goes away.
                TextField("Rate", value: rateFieldBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .focused($rateFieldFocused)
                    .onChange(of: rateFieldFocused) { _, focused in
                        if !focused { commitRateDraft() }
                    }
                    .onDisappear(perform: commitRateDraft)
                Text(appModel.secondaryCurrencyCode)
                    .foregroundStyle(.secondary)
            }
            Button(action: fetchRate) {
                HStack {
                    SettingsRowLabel(isFetchingRate ? Text("Fetching rate...") : Text("Fetch current rate"),
                                     glyph: "arrow.clockwise")
                    Spacer()
                    if isFetchingRate { ProgressView() }
                }
            }
            .disabled(isFetchingRate)
        } header: {
            Text("Display conversion rate")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let rateFetchNote {
                    Label(rateFetchNote,
                          systemImage: rateFetchFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(rateFetchFailed ? Theme.statusProgress : .secondary)
                }
                Text("Example: \(CurrencyFormatter.string(100, code: appModel.baseCurrencyCode)) = \(appModel.secondaryString(100)). Changing this rate updates converted displays; original entry amounts do not change.")
            }
        }
    }

    @ViewBuilder
    private var developerSupabaseContent: some View {
        HStack(spacing: 12) {
            SettingsRowGlyph(glyph: "network")
            TextField("Project URL", text: Bindable(appModel).supabaseURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        HStack(spacing: 12) {
            SettingsRowGlyph(glyph: "key.horizontal")
            TextField("Publishable key", text: Bindable(appModel).supabaseKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        Picker(selection: Bindable(appModel).workspaceEnvironment) {
            ForEach(AppModel.WorkspaceEnvironment.allCases) { environment in
                Text(environment.title).tag(environment)
            }
        } label: {
            SettingsRowLabel("Workspace", glyph: "externaldrive")
        }
        .pickerStyle(.menu)
        .tint(valueGray)
        .accessibilityIdentifier("settings.workspace")
    }

    @ViewBuilder
    private var developerSyncContent: some View {
        valueRow("Status", value: appModel.syncMessage)
        valueRow("Pending", value: "\(pendingSyncCount)")
        if let lastSyncAt = appModel.lastSyncAt {
            valueRow("Last sync", value: DateFormat.dotted(lastSyncAt))
        }
        Button {
            Task { await appModel.syncNow(context: context) }
        } label: {
            HStack {
                SettingsRowLabel(appModel.isSyncing ? Text("Syncing...") : Text("Sync now"),
                                 glyph: "arrow.triangle.2.circlepath")
                Spacer()
                if appModel.isSyncing { ProgressView() }
            }
        }
        .disabled(appModel.isSyncing || !appModel.isSupabaseConfigured)

        if appModel.syncConflictCount > 0 {
            Button {
                Task { await appModel.keepLocalConflictChanges(context: context) }
            } label: {
                SettingsRowLabel("Keep changes from this iPhone", glyph: "iphone")
            }
            .disabled(appModel.isSyncing)

            Button {
                pendingSyncRecoveryAction = .useCloudCopy
            } label: {
                SettingsRowLabel("Use cloud copy", glyph: "icloud.and.arrow.down")
            }
            .disabled(appModel.isSyncing || isResettingLocalData)
        }
    }

    @ViewBuilder
    private var developerDataContent: some View {
        developerButton(title: "Reset and pull",
                        glyph: "arrow.counterclockwise",
                        value: appModel.workspaceDisplayName,
                        action: .reloadCurrent)
        Button(action: importSampleLedger) {
            SettingsRowLabel("Import sample ledger", glyph: "square.and.arrow.down")
        }
        .disabled(isResettingLocalData)
        Button(action: seedStressDataset) {
            SettingsRowLabel("Seed stress dataset", glyph: "speedometer")
        }
        .disabled(isResettingLocalData)
    }

    @ViewBuilder
    private var developerAboutContent: some View {
        valueRow("Version", value: appVersion)
        NavigationLink {
            ChangelogView()
        } label: {
            SettingsRowLabel("What's new", glyph: "sparkles")
        }
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

    private func developerButton(title: LocalizedStringKey,
                                 glyph: String,
                                 value: String,
                                 action: SyncRecoveryAction) -> some View {
        Button { pendingSyncRecoveryAction = action } label: {
            HStack {
                SettingsRowLabel(title, glyph: glyph)
                Spacer()
                if isResettingLocalData {
                    ProgressView()
                } else {
                    Text(value)
                        // Explicit gray: `.secondary` inside an accent-tinted
                        // Button renders as washed-out accent, which made this
                        // one trailing value blue while every other is gray.
                        .foregroundStyle(valueGray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .disabled(isResettingLocalData || appModel.isSyncing)
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
            return String(localized: "Unsynced changes on this iPhone will be discarded and replaced by the cloud copy. Remote rows are not deleted.")
        case .reloadCurrent, nil:
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
        let dirtyClients = FetchDescriptor<Client>(predicate: #Predicate { $0.syncStateRaw != synced })
        let dirtyEntries = FetchDescriptor<Entry>(predicate: #Predicate { $0.syncStateRaw != synced })
        let dirtyHeadings = FetchDescriptor<Heading>(predicate: #Predicate { $0.syncStateRaw != synced })
        let dirtyProjectIcons = FetchDescriptor<ProjectIconPreference>(
            predicate: #Predicate { $0.syncStateRaw != synced }
        )
        let dirtyMonthReviews = FetchDescriptor<MonthReview>(
            predicate: #Predicate { $0.syncStateRaw != synced }
        )
        let tombstones = FetchDescriptor<SyncTombstone>()
        unsupportedCurrencyCount = (try? context.fetchCount(unsupported)) ?? 0
        pendingSyncCount = ((try? context.fetchCount(dirtyClients)) ?? 0)
            + ((try? context.fetchCount(dirtyEntries)) ?? 0)
            + ((try? context.fetchCount(dirtyHeadings)) ?? 0)
            + ((try? context.fetchCount(dirtyProjectIcons)) ?? 0)
            + ((try? context.fetchCount(dirtyMonthReviews)) ?? 0)
            + ((try? context.fetchCount(tombstones)) ?? 0)
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

    /// Shows the model's rate until the user edits, then their draft.
    private var rateFieldBinding: Binding<Double> {
        Binding(
            get: { rateDraft ?? appModel.rate },
            set: { rateDraft = $0 }
        )
    }

    /// Push the finished edit into the model in one write — the same
    /// commit-on-leave contract as the client rename in `ClientDetailView`.
    private func commitRateDraft() {
        guard let draft = rateDraft else { return }
        rateDraft = nil
        let normalized = AppModel.validExchangeRate(draft, fallback: appModel.rate)
        guard normalized != appModel.rate else { return }
        appModel.rate = normalized
    }

    /// One-tap rate refresh. Fetch only ever runs on this explicit tap — the
    /// typed-in rate stays authoritative, this just saves looking it up.
    private func fetchRate() {
        guard !isFetchingRate else { return }
        isFetchingRate = true
        rateFetchNote = nil
        let base = appModel.baseCurrencyCode
        let secondary = appModel.secondaryCurrencyCode
        Task { @MainActor in
            do {
                appModel.rate = try await ExchangeRateService.fetch(base: base, secondary: secondary)
                // The fetched value replaces whatever was mid-edit; keeping a
                // stale draft would visually override the fetch result.
                rateDraft = nil
                rateFetchFailed = false
                rateFetchNote = String(localized: "Rate updated")
            } catch {
                rateFetchFailed = true
                rateFetchNote = error.localizedDescription
            }
            isFetchingRate = false
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
            if inserted > 0 { appModel.queueSync(context: context) }
            refreshCounts()
        } catch {
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
        guestLedger = GuestLedgerMigration.guestLedgerSummary()
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
            case .reloadCurrent, .useCloudCopy:
                error = await appModel.resetLocalDataAndPull(context: context)
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
private struct SettingsRowLabel: View {
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
