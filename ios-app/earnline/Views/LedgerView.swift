import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Heading.date, order: .reverse) private var headings: [Heading]

    /// The one aggregation pass over the whole ledger, cached across body
    /// evaluations. `LedgerView.body` re-evaluates many times around launch
    /// (query delivery, appearance, toolbar/safe-area setup), and rebuilding
    /// the snapshot inline made each of those a full SwiftData walk — on a
    /// several-thousand-line ledger that was seconds of white screen before
    /// the first frame. Refreshed by `ModelContext.didSave` (every edit,
    /// insert, delete, import, undo, and sync pull in this app persists
    /// through a save) and by the pricing task below for currency changes,
    /// which don't touch the store.
    @State private var ledgerSnapshot: Insights.LedgerSnapshot?
    /// Trailing months currently materialized — see `refreshLedgerSnapshot`.
    @State private var windowMonthCount = LedgerView.initialWindowMonths
    /// The native List reports its top visible target. Its ID contains the
    /// represented month, so scrolling never needs a geometry preference from
    /// every row.
    @State private var topVisibleLedgerTarget: LedgerScrollTarget?
    /// Coalesces sentinel and month-boundary prefetch requests. SwiftData work
    /// happens in a later task, never inside a scroll-position callback.
    @State private var isExtendingLedgerWindow = false
    /// Coalesces the save burst a sync pass produces — see `scheduleSnapshotRefresh`.
    @State private var isSnapshotRefreshScheduled = false
    /// Full-ledger snapshot for search, built when search opens: search spans
    /// every month, not just the materialized window.
    @State private var searchSnapshot: Insights.LedgerSnapshot?
    /// Filter-menu inventory (months, clients, projects) gathered in the same
    /// pass, so the native menu never walks the store per render.
    @State private var searchFilterSource: EntrySearch.FilterSource?
    /// Hit count and earned total for the active search, computed once per
    /// query/token/store change.
    ///
    /// These were computed properties reading `rowBuilder.searchHits`, which
    /// walks every client's entries. `rowBuilder` is rebuilt on every body
    /// evaluation and the hits were read four times per render (header count,
    /// empty-state check, earned total, and the total's own re-read) — so each
    /// keystroke in the search field cost four full-ledger scans. Only the two
    /// scalars are kept: holding `[Entry]` in view state would also mean holding
    /// models a sync pull can invalidate underneath it.
    @State private var searchStats = SearchStats()

    struct SearchStats: Equatable {
        var hitCount = 0
        var earnedTotal: Decimal = .zero
    }

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
    @State private var tour = FirstRunTourState()

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

    /// One scan per query/token/store change, replacing the four per render.
    private func refreshSearchStats() {
        guard isSearching else {
            searchStats = SearchStats()
            return
        }
        let hits = rowBuilder.searchHits
        searchStats = SearchStats(
            hitCount: hits.count,
            earnedTotal: hits.reduce(.zero) { total, entry in
                guard entry.status.isIncludedInEarnedTotals else { return total }
                return total + app.toBase(entry.amount, code: entry.currencyCode)
            }
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

    /// How many trailing months the ledger materializes. Launch fetches only
    /// this window (a date-scoped SQL fetch — the whole table is never
    /// faulted); scrolling toward the bottom extends it. Eight gives the
    /// summary trend enough room to remain continuous before prefetch begins.
    private static let initialWindowMonths = 8
    private static let windowExtensionMonths = 12

    private var windowStart: Date {
        let thisMonth = DateFormat.monthStart(of: .now)
        return Calendar.current.date(byAdding: .month,
                                     value: -(windowMonthCount - 1),
                                     to: thisMonth) ?? .distantPast
    }

    private func refreshLedgerSnapshot() {
        let start = windowStart
        let inWindow = FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= start })
        let entries = (try? context.fetch(inWindow)) ?? []
        // Whole-store facts come from SQL counts, not from walking rows.
        let older = FetchDescriptor<Entry>(predicate: #Predicate { $0.date < start })
        let olderCount = (try? context.fetchCount(older)) ?? 0
        let inProgressRaw = EntryStatus.inProgress.rawValue
        let pending = FetchDescriptor<Entry>(predicate: #Predicate { $0.statusRaw == inProgressRaw })
        let pendingCount = (try? context.fetchCount(pending)) ?? 0
        // Notes are independent ledger events. Include their months in the
        // window even when a month has no income rows, and let an older note
        // request the same incremental history prefetch as an older entry.
        let visibleHeadingMonths = headings.compactMap { heading -> Date? in
            guard !heading.isInvalidated, heading.date >= start else { return nil }
            return DateFormat.monthStart(of: heading.date)
        }
        let hasOlderHeadings = headings.contains { heading in
            !heading.isInvalidated && heading.date < start
        }
        ledgerSnapshot = app.insights.ledgerSnapshot(windowed: entries,
                                                     hasOlderMonths: olderCount > 0 || hasOlderHeadings,
                                                     hasAnyEntries: olderCount > 0 || !entries.isEmpty,
                                                     pendingCount: pendingCount,
                                                     additionalMonths: visibleHeadingMonths)
        // Search spans every month, not just the window; keep its full
        // snapshot in step while it's open.
        if isSearching {
            searchSnapshot = app.insights.ledgerSnapshot(clients)
            refreshSearchStats()
        }
    }

    /// Coalesce a burst of saves into one re-aggregation. A sync pass saves
    /// three times in quick succession, and an import saves once per batch;
    /// re-aggregating per save was pure waste, since only the last state shows.
    private func scheduleSnapshotRefresh() {
        guard !isSnapshotRefreshScheduled else { return }
        isSnapshotRefreshScheduled = true
        Task { @MainActor in
            await Task.yield()
            isSnapshotRefreshScheduled = false
            guard !Task.isCancelled else { return }
            refreshLedgerSnapshot()
            if let snapshot = ledgerSnapshot {
                tour.entrySaved(app: app, hasAnyEntries: snapshot.hasEntries)
            }
        }
    }

    /// Materialize older months once the user nears the bottom of the window
    /// (the load-older sentinel row) or scrolls the summary pill close to the
    /// window's edge, where the six-month trend would otherwise miss data.
    private func requestLedgerWindowExtension() {
        guard ledgerSnapshot?.hasOlderMonths == true, !isExtendingLedgerWindow else { return }
        isExtendingLedgerWindow = true
        // A List can prefetch the sentinel while the user is still scrolling.
        // Yielding separates the SQL fetch from that scroll update, and the
        // flag coalesces repeated sentinel/top-row signals into one extension.
        Task { @MainActor in
            await Task.yield()
            defer { isExtendingLedgerWindow = false }
            guard !Task.isCancelled, ledgerSnapshot?.hasOlderMonths == true else { return }
            windowMonthCount += Self.windowExtensionMonths
            refreshLedgerSnapshot()
        }
    }

    private func prefetchLedgerWindowIfNeeded(for displayedMonth: Date) {
        guard LedgerWindowPrefetch.needsExtension(
            for: displayedMonth,
            windowStart: windowStart,
            hasOlderMonths: ledgerSnapshot?.hasOlderMonths == true
        ) else { return }
        requestLedgerWindowExtension()
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
    /// Bottom chrome replicates Apple's iOS 26 list screens (Notes, Mail):
    /// the system bottom toolbar carries a "…" circle, the resting search
    /// field, and a "+" circle. `.searchable` stays attached so the field
    /// docks into the toolbar's search slot; the system owns its focus,
    /// cancel affordance, keyboard, and expand/collapse choreography.
    private var ledgerNavigationContent: some View {
        ledgerCore
            .navigationDestination(for: LedgerRoute.self, destination: navigationDestination)
            .toolbar(.hidden, for: .navigationBar)
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
                    searchSnapshot = app.insights.ledgerSnapshot(clients)
                    searchFilterSource = buildSearchFilterSource()
                    refreshSearchStats()
                } else {
                    search.query = ""
                    search.tokens = []
                    searchSnapshot = nil
                    searchFilterSource = nil
                    searchStats = SearchStats()
                }
            }
            // The query and the token chips are the only other inputs to the
            // hit scan, so this is the complete refresh set.
            .onChange(of: search.query) { _, _ in refreshSearchStats() }
            .onChange(of: search.tokens) { _, _ in refreshSearchStats() }
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
        // The single first-action spotlight rides above the whole ledger
        // surface. Sheets naturally cover it while a person adds a client.
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if tour.isPresented, sheetRoute == nil, !isSearching {
                FirstRunTourOverlay(tour: tour, anchors: anchors)
            }
        }
        .animation(.smooth(duration: 0.3), value: tour.isPresented)
    }

    // MARK: Header

    // Kept in its own view so a scroll-driven `displayedMonth` change re-renders
    // only the summary cards. Reading `displayedMonth` (or the totals derived
    // from it) directly here would register the whole `LedgerView.body` as an
    // observer, rebuilding the ledger rows — every month, client, and entry —
    // each time the top month ticks over. That rebuild was the scroll hitch.
    private func header(monthlyTotals: [Int: Decimal]) -> some View {
        LedgerSummaryHeader(
            monthlyTotals: monthlyTotals,
            isSearching: isSearching,
            searchHitCount: searchStats.hitCount,
            searchEarnedTotal: searchStats.earnedTotal,
            hasSearchFilter: hasSearchFilter,
            onOpenStats: { sheetRoute = .insights }
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
            if let snapshot = ledgerSnapshot {
                if isSearching {
                    searchListContent(snapshot)
                } else if !rowBuilder.hasContent(in: snapshot) {
                    EmptyStateView(onStart: startFirstLine)
                        .tourAnchor(.emptyStateCTA)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } else {
                    rowsView(ledgerRows(snapshot))
                    // Load-older sentinel: scrolling it into view requests the
                    // next chunk after the current scroll update completes.
                    if !isSearching, snapshot.hasOlderMonths {
                        Color.clear
                            .frame(height: 1)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear(perform: requestLedgerWindowExtension)
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
        .scrollPosition(id: $topVisibleLedgerTarget, anchor: .top)
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
            if let snapshot = ledgerSnapshot {
                header(monthlyTotals: snapshot.earnedTotalByMonth)
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
        .onChange(of: topVisibleLedgerTarget) { _, target in
            guard !isSearching else { return }
            updateDisplayedMonth(target?.representedMonth)
        }
        // Runs after the first frame commits — the app appears immediately and
        // the ledger fills in a beat later — then again when the currency
        // settings re-price the totals. Data edits arrive via `didSave` below.
        .task(id: pricingRevision) {
            refreshLedgerSnapshot()
            if let snapshot = ledgerSnapshot {
                tour.evaluateStart(app: app, hasAnyEntries: snapshot.hasEntries)
            }
        }
        // Every mutation in this app persists through a context save (the
        // AppModel.save contract, plus the sync pass's own saves), so this is
        // the one complete invalidation signal for the cached snapshot.
        //
        // Filtered and coalesced, though. One sync pass saves three times, and
        // every save used to trigger a full re-aggregation — two fetches and two
        // counts apiece. The host also keeps one container alive per workspace,
        // so an unrelated container's save refreshed this ledger too.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            guard (notification.object as? ModelContext) === context else { return }
            scheduleSnapshotRefresh()
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

    // MARK: Search filters

    /// One walk over the store at search-open time: distinct months arrive
    /// with the full snapshot; clients and their distinct project names are
    /// collected here so native menu rendering is pure lookup.
    private func buildSearchFilterSource() -> EntrySearch.FilterSource {
        var source = EntrySearch.FilterSource()
        source.months = searchSnapshot?.months ?? []
        var seenProjects: Set<String> = []
        var projects: [String] = []
        for client in clients where !client.isInvalidated {
            source.clients.append(.init(id: client.id, name: client.name))
            for entry in client.entries where !entry.isInvalidated {
                guard let project = entry.project, !project.isEmpty,
                      seenProjects.insert(EntrySearch.normalized(project)).inserted else { continue }
                projects.append(project)
            }
        }
        source.projects = projects.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return source
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
        saveError = app.delete(e, context: context)
        if saveError == nil {
            feedback.success += 1
        }
    }

    // MARK: Add income

    private func toggleComposer(_ client: Client, month: Date) {
        let m = DateFormat.monthStart(of: month)
        withAnimation(.smooth(duration: 0.3)) {
            if activeComposerClient?.id == client.id, isComposerMonth(m) {
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

    private func newProject() {
        if clients.isEmpty { sheetRoute = .newClient; return }
        if let c = mostRecentClient { openComposer(for: c, month: app.displayedMonth) }
    }

    private func startFirstLine() {
        if clients.isEmpty { sheetRoute = .newClient } else { newProject() }
    }

    private var mostRecentClient: Client? {
        clients.max { $0.createdAt < $1.createdAt } ?? clients.first
    }

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
        if saveChanges() { app.stageUndo(snapshot) }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        saveError = app.save(context)
        return saveError == nil
    }

    // MARK: Month tracking

    private func updateDisplayedMonth(_ month: Date?) {
        guard let month else { return }
        let m = DateFormat.monthStart(of: month)
        if !Calendar.current.isDate(m, equalTo: app.displayedMonth, toGranularity: .month) {
            app.displayedMonth = m
            // Preload the next twelve months before the six-month summary trend
            // reaches the edge of the materialized data. The task itself runs
            // after this scroll callback returns.
            prefetchLedgerWindowIfNeeded(for: m)
        }
    }

    private func isComposerMonth(_ month: Date) -> Bool {
        guard let composerMonth = composerRoute?.month else { return false }
        return Calendar.current.isDate(month, equalTo: composerMonth, toGranularity: .month)
    }
}
