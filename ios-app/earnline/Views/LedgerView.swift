import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Heading.date, order: .reverse) private var headings: [Heading]

    /// Keeps cache invalidation and deferred SwiftData aggregation outside the
    /// navigation view. The screen still owns routes, sheets, and user input.
    @State private var snapshotCache = LedgerSnapshotCache()

    /// Mutually exclusive UI presentations are represented as typed routes,
    /// avoiding combinations such as two active sheets or two delete alerts.
    @State private var navigationPath: [LedgerRoute] = []
    @State private var sheetRoute: LedgerSheetRoute?
    @State private var confirmationRoute: LedgerConfirmationRoute?
    @State private var composerRoute: LedgerComposerRoute?
    @State private var search = LedgerSearchState()
    @State private var feedback = LedgerFeedbackState()
    @State private var didRunDemo = false
    @State private var saveError: String?

    // MARK: Derived

    private var isSearching: Bool { search.isPresented }
    private var searchQuery: String { search.query }
    private var rowBuilder: LedgerRowBuilder {
        LedgerRowBuilder(
            clients: clients,
            headings: headings,
            app: app,
            composerRoute: composerRoute,
            searchQuery: searchQuery,
            searchTokens: search.tokens
        )
    }

    private var activeComposerClient: Client? { rowBuilder.activeComposerClient }
    private var hasSearchFilter: Bool { rowBuilder.hasSearchFilter }
    private var ledgerSnapshot: Insights.LedgerSnapshot? { snapshotCache.ledgerSnapshot }
    private var searchSnapshot: Insights.LedgerSnapshot? { snapshotCache.searchSnapshot }
    private var searchFilterSource: EntrySearch.FilterSource? { snapshotCache.searchFilterSource }
    private var searchStats: LedgerSnapshotCache.SearchStats { snapshotCache.searchStats }
    /// A large first-earnings header is useful context but cannot remain fixed
    /// above the onboarding card at accessibility sizes: it would cover the
    /// card as the person scrolls to its primary action. Let it scroll with the
    /// card instead, preserving a clear reading order and a reachable action.
    private var showsInlineFirstEarningsHeader: Bool {
        dynamicTypeSize.isAccessibilitySize
            && !isSearching
            && ledgerSnapshot?.hasEntries == false
    }

    /// Everything the cache needs for one aggregation pass, resolved together so
    /// a deferred pass cannot see a half-updated set.
    private var snapshotInputs: LedgerSnapshotCache.Inputs {
        LedgerSnapshotCache.Inputs(
            context: context,
            clients: clients,
            headings: headings,
            app: app,
            isSearching: isSearching,
            rowBuilder: rowBuilder
        )
    }

    private func ledgerRows(_ snapshot: Insights.LedgerSnapshot) -> [LedgerRow] {
        rowBuilder.rows(in: snapshot, isSearching: isSearching, searchSnapshot: searchSnapshot)
    }

    /// The snapshot's only inputs that change *without* a context save: the
    /// currency pair and rate re-price every total. Read in body via
    /// `.task(id:)`, so a committed rate edit re-runs the snapshot task.
    private struct PricingRevision: Hashable {
        let baseCurrencyCode: String
        let secondaryCurrencyCode: String
        let rate: Double
    }

    private var pricingRevision: PricingRevision {
        PricingRevision(baseCurrencyCode: app.baseCurrencyCode,
                        secondaryCurrencyCode: app.secondaryCurrencyCode,
                        rate: app.rate)
    }

    /// `ModelContext.didSave` remains a fallback for saves outside the mutation
    /// store, but device saves need a deterministic invalidation signal for the
    /// cached summary snapshot.
    private struct LedgerRevision: Hashable {
        let pricing: PricingRevision
        let dataRevision: Int
    }

    private var ledgerRevision: LedgerRevision {
        LedgerRevision(pricing: pricingRevision, dataRevision: mutations.dataRevision)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ledgerNavigationContent
        }
        // Settings is presented by `WorkspaceContainerHost` (bound to
        // `app.showSettings`) so it survives the `.id` reset on a workspace
        // switch; every other sheet is scoped to this ledger's lifetime.
        .sheet(item: $sheetRoute, content: sheetContent)
        .alert(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmationRoute != nil },
                set: { if !$0 { confirmationRoute = nil } }
            ),
            presenting: confirmationRoute
        ) { route in
            Button("Delete", role: .destructive) {
                confirmDeletion(route)
                confirmationRoute = nil
            }
            Button("Cancel", role: .cancel) { confirmationRoute = nil }
        } message: { confirmationMessage($0) }
        .saveErrorAlert($saveError)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback.impact)
        .sensoryFeedback(.success, trigger: feedback.success)
    }

    @ViewBuilder
    private func sheetContent(_ route: LedgerSheetRoute) -> some View {
        switch route {
        case .editEntry(let id):
            if let entry = entry(withID: id) {
                EditEntrySheet(entry: entry, clients: clients)
            }
        case .newClient:
            NewClientSheet(existingClients: clients) { newClient in
                openComposer(for: newClient, month: app.displayedMonth)
            }
        case .pasteLines:
            PasteLinesSheet(clients: clients, defaultClient: mostRecentClient)
        case .insights:
            InsightsView()
        case .pending:
            PendingView()
        case .newHeading:
            LedgerHeadingEditor(
                initialTitle: "",
                initialDate: app.displayedMonth,
                allowsDeletion: false,
                onSave: { saveHeading(title: $0, date: $1, headingID: nil) }
            )
        case .editHeading(let id):
            if let heading = heading(withID: id) {
                LedgerHeadingEditor(
                    initialTitle: heading.title,
                    initialDate: heading.date,
                    allowsDeletion: true,
                    onSave: { saveHeading(title: $0, date: $1, headingID: id) },
                    onDelete: { deleteHeading(withID: id) }
                )
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmationRoute {
        case .deleteEntry: String(localized: "Delete income line?")
        case .deleteHeading: String(localized: "Delete event note?")
        case nil: ""
        }
    }

    @ViewBuilder
    private func confirmationMessage(_ route: LedgerConfirmationRoute) -> some View {
        switch route {
        case .deleteEntry(let id):
            if let entry = entry(withID: id) {
                Text("\(CurrencyFormatter.string(entry.amount, code: entry.currencyCode)) · \(entry.task)")
            }
        case .deleteHeading(let id):
            if let heading = heading(withID: id) {
                Text(heading.title.isEmpty ? String(localized: "Untitled") : heading.title)
            }
        }
    }

    private func confirmDeletion(_ route: LedgerConfirmationRoute) {
        switch route {
        case .deleteEntry(let id):
            if let entry = entry(withID: id) { delete(entry) }
        case .deleteHeading(let id):
            deleteHeading(withID: id)
        }
    }

    /// The inner navigation surface is kept separate from the sheet tree so
    /// SwiftUI can type-check toolbar and search modifiers independently.
    ///
    /// The chrome is the bottom bar: "…", the docked system search field, "+".
    /// See `LedgerBottomBarItems`. A previous change moved "…" and "+" up into
    /// the navigation bar to silence an iOS 26 UIKit hierarchy log; that traded
    /// the designed layout for a console message and is not a trade this screen
    /// makes. If the log returns, fix it inside the toolbar composition.
    private var ledgerNavigationContent: some View {
        ledgerCore
            .navigationDestination(for: LedgerRoute.self, destination: navigationDestination)
            .searchable(text: $search.query,
                        tokens: $search.tokens,
                        isPresented: $search.isPresented,
                        placement: .automatic,
                        prompt: "Search income") { token in
                Label(token.label, systemImage: token.systemImage)
            }
            .toolbar { bottomToolbar }
            .onChange(of: search.isPresented) { _, searching in
                if searching {
                    composerRoute = nil
                    // One full pass, user-initiated: search must span every
                    // month, while the ledger itself stays windowed.
                    snapshotCache.beginSearch(snapshotInputs)
                } else {
                    search.query = ""
                    search.tokens = []
                    snapshotCache.endSearch()
                }
            }
            // The query and the token chips are the only other inputs to the
            // hit scan, so this is the complete refresh set.
            .onChange(of: search.query) { _, _ in snapshotCache.refreshSearchStats(snapshotInputs) }
            .onChange(of: search.tokens) { _, _ in snapshotCache.refreshSearchStats(snapshotInputs) }
            .onAppear(perform: runDemoIfNeeded)
            .onChange(of: clients.count) { _, _ in runDemoIfNeeded() }
    }

    private var bottomToolbar: some ToolbarContent {
        LedgerBottomBarItems(
            clients: clients,
            pendingCount: ledgerSnapshot?.pendingCount ?? 0,
            isSearching: isSearching,
            filterSource: searchFilterSource,
            searchTokens: $search.tokens,
            onInsights: { sheetRoute = .insights },
            onPending: { sheetRoute = .pending },
            onSettings: { app.showSettings = true },
            onIncome: { client in
                if let client {
                    openComposer(for: client, month: app.displayedMonth)
                } else {
                    sheetRoute = .newClient
                }
            },
            onNewClient: { sheetRoute = .newClient },
            onNewHeading: { sheetRoute = .newHeading },
            onPasteLines: { sheetRoute = .pasteLines }
        )
    }

    @ViewBuilder
    private func navigationDestination(_ route: LedgerRoute) -> some View {
        switch route {
        case .client(let id):
            if let client = client(withID: id) {
                ClientDetailView(client: client)
            }
        }
    }

    /// Ledger list + undo toast. Bottom chrome is a SwiftUI safe-area bar so
    /// it never inserts a UIKit toolbar beneath the hosting controller.
    private var ledgerCore: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            scrollContent
        }
        .undoToastHost()
    }

    // MARK: Header

    // Kept in its own view so a scroll-driven `displayedMonth` change re-renders
    // only the summary cards. Reading `displayedMonth` (or the totals derived
    // from it) directly here would register the whole `LedgerView.body` as an
    // observer, rebuilding the ledger rows — every month, client, and entry —
    // each time the top month ticks over. That rebuild was the scroll hitch.
    private func header(monthlyTotals: [Int: Decimal], hasAnyEntries: Bool) -> some View {
        LedgerSummaryHeader(
            monthlyTotals: monthlyTotals,
            isSearching: isSearching,
            searchHitCount: searchStats.hitCount,
            searchEarnedTotal: searchStats.earnedTotal,
            hasSearchFilter: hasSearchFilter,
            hasAnyEntries: hasAnyEntries
        )
    }

    // MARK: Scroll content (List → native swipe actions)

    private var scrollContent: some View {
        // The row model and the summary header share the cached
        // `ledgerSnapshot` (one aggregation pass, refreshed by the task below
        // only when `ledgerRevision` changes). Body re-evaluations — and there
        // are many around launch — reuse it for free, and scrolling never
        // touches it: the header owns the `displayedMonth` read.
        List {
            if showsInlineFirstEarningsHeader, let snapshot = ledgerSnapshot {
                header(monthlyTotals: snapshot.earnedTotalByMonth, hasAnyEntries: snapshot.hasEntries)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            }

            if let snapshot = ledgerSnapshot {
                if isSearching {
                    searchListContent(snapshot)
                } else if rowBuilder.hasContent(in: snapshot) {
                    rowsView(ledgerRows(snapshot))
                    // Load-older sentinel: scrolling it into view requests the
                    // next chunk after the current scroll update completes.
                    if !isSearching, snapshot.hasOlderMonths {
                        Color.clear
                            .frame(height: 1)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear { snapshotCache.requestWindowExtension(snapshotInputs) }
                    }
                }
            }
            Color.clear
                .frame(height: 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .coordinateSpace(name: "ledger")
        // Pull-to-refresh mirrors the standard syncable-list affordance; a
        // no-op while Supabase isn't configured. Disabled in search mode so
        // a pull doesn't fight the keyboard.
        .refreshable {
            guard !isSearching, app.isSupabaseConfigured else { return }
            await app.syncNow(context: context)
        }
        // The floating summary cards ride a top `safeAreaBar` — a real pinned
        // bar, which is what a scroll edge effect attaches to. The native soft
        // effect then frosts rows into a blurred band as they slide up behind
        // the cards (Figma's "Scroll Edge Effect - Soft"), progressively, and
        // stays put at rest. A plain `safeAreaInset` gave the effect no bar to
        // frost against, so the top read as a hard cut with no blur.
        .safeAreaBar(edge: .top) {
            if !showsInlineFirstEarningsHeader, let snapshot = ledgerSnapshot {
                header(monthlyTotals: snapshot.earnedTotalByMonth, hasAnyEntries: snapshot.hasEntries)
            }
        }
        // UIKit replaces the docked bottom-bar items with its full search
        // field and Cancel control once search expands. Keep the one native
        // Filters menu reachable in the same lower chrome, above that field,
        // rather than reviving the former horizontal chip strip.
        .safeAreaBar(edge: .bottom) {
            if isSearching, let source = searchFilterSource {
                HStack {
                    LedgerSearchFiltersMenu(source: source, tokens: $search.tokens)
                        .buttonStyle(.glass)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(MonthAnchorKey.self) { anchors in
            guard !isSearching else { return }
            updateDisplayedMonth(anchors)
        }
        // Runs after the first frame commits — the app appears immediately and
        // the ledger fills in a beat later — then again when the currency
        // settings re-price the totals. Data edits arrive via `didSave` below.
        .task(id: ledgerRevision) {
            snapshotCache.refreshLedgerSnapshot(snapshotInputs)
        }
        // Every mutation in this app persists through a context save (the
        // LedgerMutationStore.save contract, plus the sync pass's own saves), so this is
        // the one complete invalidation signal for the cached snapshot.
        //
        // Filtered and coalesced, though. One sync pass saves three times, and
        // every save used to trigger a full re-aggregation — two fetches and two
        // counts apiece. The host also keeps one container alive per workspace,
        // so an unrelated container's save refreshed this ledger too.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            guard (notification.object as? ModelContext) === context else { return }
            snapshotCache.scheduleSnapshotRefresh(snapshotInputs)
        }
    }

    @ViewBuilder
    private func searchListContent(_ snapshot: Insights.LedgerSnapshot) -> some View {
        if !hasSearchFilter {
            // Visible only when the suggestion overlay has nothing to offer
            // (an empty ledger); otherwise the browse filters cover this.
            ContentUnavailableView(
                "Search income",
                systemImage: "magnifyingglass",
                description: Text("Find lines by client, project, task, amount, or date.")
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if searchStats.hitCount == 0 {
            if EntrySearch.normalized(searchQuery).isEmpty {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ContentUnavailableView.search(text: searchQuery)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } else {
            rowsView(ledgerRows(snapshot))
        }
    }

    private func rowsView(_ rows: [LedgerRow]) -> some View {
        LedgerRowsView(
            rows: rows,
            isSearching: isSearching,
            activeComposerClientID: activeComposerClient?.id,
            composerMonth: composerRoute?.month,
            onOpenClient: { navigationPath.append(.client($0)) },
            onToggleComposer: { toggleComposer($0, month: $1) },
            onSetStatus: setStatus,
            onEditEntry: { sheetRoute = .editEntry($0) },
            onDeleteEntry: { confirmationRoute = .deleteEntry($0) },
            onEditHeading: { sheetRoute = .editHeading($0) },
            onDeleteHeading: { confirmationRoute = .deleteHeading($0) }
        )
    }

    // MARK: Entry actions

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) { e.status = s; e.markDirty() }
        if saveChanges() {
            feedback.impact += 1
        }
    }

    private func delete(_ e: Entry) {
        saveError = mutations.delete(e, context: context)
        if saveError == nil {
            feedback.success += 1
        }
    }

    // MARK: Add income

    private func toggleComposer(_ client: Client, month: Date) {
        let m = DateFormat.monthStart(of: month)
        withAnimation(.smooth(duration: 0.3)) {
            if activeComposerClient?.id == client.id, rowBuilder.isComposerMonth(m) {
                composerRoute = nil
            } else {
                composerRoute = LedgerComposerRoute(clientID: client.id, month: m)
            }
        }
    }

    private func openComposer(for client: Client, month: Date) {
        withAnimation(.smooth(duration: 0.3)) {
            composerRoute = LedgerComposerRoute(
                clientID: client.id,
                month: DateFormat.monthStart(of: month)
            )
        }
    }

    private var mostRecentClient: Client? {
        clients
            .filter { !$0.isInvalidated }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Skips invalidated models for the same reason every other client read
    /// here does: a sync pull can delete one while this body is being evaluated.
    private func client(withID id: UUID) -> Client? {
        clients.first { !$0.isInvalidated && $0.id == id }
    }

    private func entry(withID id: UUID) -> Entry? {
        for client in clients where !client.isInvalidated {
            if let entry = client.entries.first(where: { !$0.isInvalidated && $0.id == id }) {
                return entry
            }
        }
        return nil
    }

    private func heading(withID id: UUID) -> Heading? {
        headings.first { !$0.isInvalidated && $0.id == id }
    }

    /// Launch-argument hooks for UI automation: each opens one surface
    /// directly so visual checks don't depend on scripted taps.
    private func runDemoIfNeeded() {
        #if DEBUG
        guard !didRunDemo else { return }
        if AppModel.hasUIAutomationLaunchFlag("-demoComposer"), let client = clients.first {
            // The fixture is inserted by the root store task. Wait for its
            // query delivery instead of consuming this one-shot hook before
            // a client exists.
            didRunDemo = true
            openComposer(for: client, month: .now)
        } else if AppModel.hasUIAutomationLaunchFlag("-demoSettings")
                    || AppModel.hasUIAutomationLaunchFlag("-demoDeveloperSettings") {
            didRunDemo = true
            app.showSettings = true
        } else if AppModel.hasUIAutomationLaunchFlag("-demoHeadingEditor") {
            didRunDemo = true
            sheetRoute = .newHeading
        } else if AppModel.hasUIAutomationLaunchFlag("-demoEdit") {
            didRunDemo = true
            if let entry = clients.first(where: { !$0.entries.isEmpty })?.entries.first {
                sheetRoute = .editEntry(entry.id)
            }
        } else if AppModel.hasUIAutomationLaunchFlag("-demoSearch") {
            didRunDemo = true
            search.isPresented = true
        } else if AppModel.hasUIAutomationLaunchFlag("-demoInsights") {
            didRunDemo = true
            sheetRoute = .insights
        } else if AppModel.hasUIAutomationLaunchFlag("-demoClientProfile"),
                  let stressClient = clients.first(where: { $0.name == "Stress Client 1" }) {
            didRunDemo = true
            navigationPath.append(.client(stressClient.id))
        }
        #endif
    }

    // MARK: Event notes (persisted as Heading for sync compatibility)

    private func saveHeading(title: String, date: Date, headingID: UUID?) -> Bool {
        guard !title.isEmpty else { return false }
        if let headingID {
            guard let heading = heading(withID: headingID) else { return false }
            heading.title = title
            heading.date = date
            heading.markDirty()
        } else {
            context.insert(Heading(title: title,
                                   date: date,
                                   sortIndex: 0))
        }
        return saveChanges()
    }

    private func deleteHeading(withID id: UUID) {
        if let heading = heading(withID: id) { delete(heading) }
    }

    private func delete(_ h: Heading) {
        let snapshot = UndoableDelete.heading(HeadingSnapshot(h))
        SyncDeleteQueue.enqueue(.heading, id: h.id, in: context)
        withAnimation(.snappy) { context.delete(h) }
        if saveChanges() { mutations.stageUndo(snapshot) }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        saveError = mutations.save(context)
        return saveError == nil
    }

    // MARK: Month tracking

    private func updateDisplayedMonth(_ anchors: [MonthAnchor]) {
        guard !anchors.isEmpty else { return }
        let anchorsAboveHeader = anchors.filter { $0.y <= 44 }
        guard let anchor = anchorsAboveHeader.max(by: { $0.y < $1.y })
            ?? anchors.min(by: { $0.y < $1.y }) else { return }
        let m = DateFormat.monthStart(of: anchor.month)
        if !Calendar.current.isDate(m, equalTo: app.displayedMonth, toGranularity: .month) {
            // The month only changes once after crossing a boundary, not for
            // every scroll tick. Owning the transaction here lets the pinned
            // summary preserve its rolling title, amount, and graph transition
            // without making the List itself animate.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.34)) {
                app.displayedMonth = m
            }
            // Preload the next twelve months before the six-month summary trend
            // reaches the edge of the materialized data. The task itself runs
            // after this scroll callback returns.
            snapshotCache.prefetchWindowIfNeeded(for: m, inputs: snapshotInputs)
        }
    }
}
