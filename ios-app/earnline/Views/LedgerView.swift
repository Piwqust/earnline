import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Heading.sortIndex) private var headings: [Heading]

    @State private var composerClient: Client?
    /// The month the open composer is anchored to — set from the section whose
    /// "+ Line" was tapped, so the composer shows there (not always the current
    /// month) and its new line defaults into that month.
    @State private var composerMonth = DateFormat.monthStart(of: .now)
    @State private var showNewClient = false
    @State private var showPaste = false
    /// Drives the system `.searchable` field (`isPresented`). When true the
    /// ledger filters in place and the bottom-toolbar actions yield to the
    /// iOS 26 Liquid Glass search bar at the bottom.
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var showInsights = false
    @State private var showPending = false
    @State private var detailClient: Client?
    @State private var editingEntry: Entry?
    @State private var renamingHeading: Heading?
    @State private var showHeadingEditor = false
    @State private var headingTitle = ""
    @State private var pendingDelete: Entry?
    @State private var pendingDeleteHeading: Heading?
    @State private var confirmEditorHeadingDelete = false
    @State private var didRunDemo = false
    @State private var saveError: String?
    @FocusState private var headingFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    // MARK: Derived

    /// `composerClient` survives in view state while a sync pull can delete
    /// the client underneath it; reading even `.id` on the invalidated model
    /// traps, so every row-building read goes through this nil-ing accessor.
    private var activeComposerClient: Client? {
        guard let composerClient, !composerClient.isInvalidated else { return nil }
        return composerClient
    }

    private func sectionHeadings(in month: Date) -> [Heading] {
        headings.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private func sectionClients(in month: Date, snapshot: Insights.LedgerSnapshot) -> [Client] {
        let key = snapshot.key(for: month)
        // `clients` arrives sortIndex-sorted from the @Query; filtering keeps
        // that order, matching what `clientsWithEntries` used to return.
        var list = clients.filter { !$0.isInvalidated && snapshot.hasEntries($0, monthKey: key) }
        if let cc = activeComposerClient, isComposerMonth(month), !list.contains(where: { $0.id == cc.id }) {
            list.append(cc)
        }
        return list
    }

    private func blocks(in month: Date, snapshot: Insights.LedgerSnapshot) -> [Block] {
        let h = sectionHeadings(in: month).map { Block.heading($0) }
        let c = sectionClients(in: month, snapshot: snapshot).map { Block.client($0) }
        return (h + c).sorted { $0.isOrderedBefore($1) }
    }

    /// The full row model, read off one `LedgerSnapshot` pass. The previous
    /// per-month filtering re-walked every client's whole entries array once
    /// per month with `Calendar` granularity compares — O(months × entries)
    /// per rebuild, which is what made a long ledger stutter on every body
    /// evaluation (each keystroke, status change, or sync tick).
    private func ledgerRows(_ snapshot: Insights.LedgerSnapshot) -> [Row] {
        if isSearching { return searchLedgerRows(snapshot) }
        var rows: [Row] = []
        for month in snapshot.months {
            let key = snapshot.key(for: month)
            rows.append(.month(month, snapshot.monthTotal(monthKey: key)))
            for block in blocks(in: month, snapshot: snapshot) {
                switch block {
                case .heading(let h): rows.append(.heading(h))
                case .client(let c):
                    rows.append(.client(c, month, snapshot.total(of: c, monthKey: key)))
                    if isComposerMonth(month), activeComposerClient?.id == c.id {
                        rows.append(.composer(c))
                    }
                    for e in snapshot.entries(of: c, monthKey: key) { rows.append(.entry(e)) }
                }
            }
        }
        return rows
    }

    /// Matching entries grouped under their month/client, newest months first
    /// (same order as the idle ledger). Headings and the composer are omitted.
    /// Month and client rows carry the earned totals of the *matches*, so the
    /// row views don't re-run the search per row.
    private func searchLedgerRows(_ snapshot: Insights.LedgerSnapshot) -> [Row] {
        guard !EntrySearch.normalized(searchQuery).isEmpty else { return [] }
        var rows: [Row] = []
        for month in snapshot.months {
            let key = snapshot.key(for: month)
            var monthRows: [Row] = []
            var monthTotal = Decimal.zero
            for block in blocks(in: month, snapshot: snapshot) {
                guard case .client(let c) = block, !c.isInvalidated else { continue }
                let matches = snapshot.entries(of: c, monthKey: key).filter { entry in
                    guard !entry.isInvalidated else { return false }
                    return EntrySearch.matches(entry, query: searchQuery, clientName: c.name)
                }
                guard !matches.isEmpty else { continue }
                let earned = matches
                    .filter { $0.status.isIncludedInEarnedTotals }
                    .reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
                monthTotal += earned
                monthRows.append(.client(c, month, earned))
                for e in matches { monthRows.append(.entry(e)) }
            }
            if !monthRows.isEmpty {
                rows.append(.month(month, monthTotal))
                rows.append(contentsOf: monthRows)
            }
        }
        return rows
    }

    /// Live hits for the compact header total (canceled excluded).
    private var searchHits: [Entry] {
        guard isSearching, !EntrySearch.normalized(searchQuery).isEmpty else { return [] }
        return clients.flatMap { client -> [Entry] in
            guard !client.isInvalidated else { return [] }
            return client.entries.filter { entry in
                guard !entry.isInvalidated else { return false }
                return EntrySearch.matches(entry, query: searchQuery, clientName: client.name)
            }
        }
    }

    private var searchEarnedTotal: Decimal {
        searchHits
            .filter { $0.status.isIncludedInEarnedTotals }
            .reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }

    private var hasContent: Bool {
        !headings.isEmpty || clients.contains { !$0.entries.isEmpty }
    }

    private var hasSearchQuery: Bool {
        !EntrySearch.normalized(searchQuery).isEmpty
    }

    var body: some View {
        NavigationStack {
            ledgerNavigationContent
        }
        // Settings is presented by `WorkspaceContainerHost` (bound to
        // `app.showSettings`) so it survives the `.id` reset on a workspace
        // switch; every other sheet is scoped to this ledger's lifetime.
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
        .sheet(isPresented: $showNewClient) {
            NewClientSheet(existingClients: clients) { newClient in
                openComposer(for: newClient, month: app.displayedMonth)
            }
        }
        .sheet(isPresented: $showPaste) {
            PasteLinesSheet(clients: clients, defaultClient: mostRecentClient)
        }
        .sheet(isPresented: $showInsights) { InsightsView() }
        .sheet(isPresented: $showPending) { PendingView() }
        .sheet(isPresented: Binding(
            get: { showHeadingEditor },
            set: {
                showHeadingEditor = $0
                if !$0 { renamingHeading = nil }
            }
        )) {
            headingEditorSheet
        }
        .alert(
            "Delete income line?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                delete(entry)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text("\(CurrencyFormatter.string(entry.amount, code: entry.currencyCode)) · \(entry.task)")
        }
        .alert(
            "Delete heading?",
            isPresented: Binding(get: { pendingDeleteHeading != nil },
                                 set: { if !$0 { pendingDeleteHeading = nil } }),
            presenting: pendingDeleteHeading
        ) { heading in
            Button("Delete", role: .destructive) {
                delete(heading)
                pendingDeleteHeading = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteHeading = nil }
        } message: { heading in
            Text(heading.title.isEmpty ? String(localized: "Untitled") : heading.title)
        }
        .saveErrorAlert($saveError)
    }

    /// The inner navigation surface is kept separate from the sheet tree so
    /// SwiftUI can type-check toolbar and search modifiers independently.
    private var ledgerNavigationContent: some View {
        ledgerCore
            .navigationDestination(item: $detailClient) { ClientDetailView(client: $0) }
            .toolbar(.hidden, for: .navigationBar)
            // Keep the action controls in the system bottom bar: it folds the
            // `.searchable` field into the same Liquid Glass surface (via
            // `.searchToolbarBehavior(.minimize)`), so no separate search bar
            // shows at rest. Floating them into an overlay removes that host and
            // a persistent "Search income" bar reappears — hence they stay here,
            // using explicit circular glass labels at the bar's native margins.
            .toolbar { bottomToolbar }
            // System search owns its focus, cancel affordance, keyboard, and
            // Liquid Glass presentation. There is no custom text field layered
            // on top of the toolbar anymore.
            .searchable(text: $searchQuery,
                        isPresented: $isSearching,
                        placement: .automatic,
                        prompt: "Search income")
            .searchToolbarBehavior(.minimize)
            .onChange(of: isSearching) { _, searching in
                if searching { composerClient = nil }
                else { searchQuery = "" }
            }
            .onAppear(perform: runDemoIfNeeded)
    }

    /// Ledger list + undo toast. Bottom chrome lives in the system toolbar
    /// (see `body`) so search, Add, and More share one Liquid Glass surface.
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
    private func header(monthlyTotals: [Int: Decimal]) -> some View {
        LedgerSummaryHeader(
            monthlyTotals: monthlyTotals,
            isSearching: isSearching,
            searchHitCount: searchHits.count,
            searchEarnedTotal: searchEarnedTotal,
            hasSearchQuery: hasSearchQuery,
            onOpenStats: { showInsights = true }
        )
    }

    // MARK: Scroll content (List → native swipe actions)

    private var scrollContent: some View {
        // One aggregation pass shared by the row model and the summary header;
        // rebuilt only when this body re-evaluates (a data change), never by
        // scrolling — the header owns the `displayedMonth` read.
        let snapshot = app.insights.ledgerSnapshot(clients)
        return List {
            if isSearching {
                searchListContent(snapshot)
            } else if !hasContent {
                EmptyStateView(onStart: startFirstLine)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } else {
                ForEach(ledgerRows(snapshot)) { row in
                    rowView(row)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(insets(for: row))
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
        // Pull-to-refresh mirrors the standard syncable-list affordance; a
        // no-op while Supabase isn't configured. Disabled in search mode so
        // a pull doesn't fight the keyboard.
        .refreshable {
            guard !isSearching, app.isSupabaseConfigured else { return }
            await app.syncNow(context: context)
        }
        .coordinateSpace(name: "ledger")
        // The floating summary cards ride a top `safeAreaBar` — a real pinned
        // bar, which is what a scroll edge effect attaches to. The native soft
        // effect then frosts rows into a blurred band as they slide up behind
        // the cards (Figma's "Scroll Edge Effect - Soft"), progressively, and
        // stays put at rest. A plain `safeAreaInset` gave the effect no bar to
        // frost against, so the top read as a hard cut with no blur.
        .safeAreaBar(edge: .top) { header(monthlyTotals: snapshot.earnedTotalByMonth) }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The bottom toolbar already provides its own native Liquid Glass
        // contrast. Keep the list edge clean instead of layering a detached
        // material gradient above the home indicator.
        .scrollEdgeEffectHidden(true, for: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(MonthAnchorKey.self) { anchors in
            updateDisplayedMonth(anchors)
        }
    }

    @ViewBuilder
    private func searchListContent(_ snapshot: Insights.LedgerSnapshot) -> some View {
        if !hasSearchQuery {
            ContentUnavailableView(
                "Search income",
                systemImage: "magnifyingglass",
                description: Text("Find lines by client, project, task, or amount.")
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if searchHits.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            ForEach(ledgerRows(snapshot)) { row in
                rowView(row)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(insets(for: row))
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        // A sync pull (remote tombstone, store reset) can delete a model after
        // `ledgerRows` was built but while its row is still in the List; one
        // more render of that row would trap reading the invalidated model
        // (the switch-workspaces-twice crash). Skip it — the next @Query
        // update removes the row for real.
        if row.isInvalidated {
            EmptyView()
        } else {
            liveRowView(row)
        }
    }

    @ViewBuilder
    private func liveRowView(_ row: Row) -> some View {
        // Every row reports its month, not just the dividers: List recycles
        // offscreen rows, so a long month whose divider has scrolled away would
        // otherwise stop feeding the summary pill and leave it stale.
        switch row {
        case .month(let m, let total):
            monthRow(m, total: total)
        case .heading(let h):
            headingRow(h)
                .background(monthAnchorReader(DateFormat.monthStart(of: h.date)))
        case .client(let c, let m, let total):
            clientHeaderRow(c, month: m, total: total)
                .background(monthAnchorReader(m))
        case .composer(let c):
            composerRow(c)
        case .entry(let e):
            entryRow(e)
                .background(monthAnchorReader(DateFormat.monthStart(of: e.date)))
        }
    }

    private func clientHeaderRow(_ client: Client, month: Date, total: Decimal) -> some View {
        ClientChip(
            client: client,
            total: total,
            isComposing: !isSearching && activeComposerClient?.id == client.id,
            showsAdd: !isSearching,
            onOpen: { detailClient = client },
            onAdd: { toggleComposer(client, month: month) }
        )
    }

    private func composerRow(_ client: Client) -> some View {
        SmartComposer(client: client, month: composerMonth)
            .transition(.opacity)
    }

    private func monthRow(_ month: Date, total: Decimal) -> some View {
        MonthDivider(title: DateFormat.month(month), total: total)
            .background(monthAnchorReader(month))
    }

    private func monthAnchorReader(_ month: Date) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: MonthAnchorKey.self,
                value: [MonthAnchor(month: month, y: geo.frame(in: .named("ledger")).minY)]
            )
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        EntryRow(
            entry: entry,
            onSetStatus: { setStatus(entry, $0) },
            onEdit: { editingEntry = entry },
            onDelete: { pendingDelete = entry }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // The app-wide `.tint(accentColor)` cascades into swipe actions, so
            // the destructive button has to reclaim the system red explicitly —
            // otherwise Delete renders in the accent color like Edit.
            Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
                .tint(Theme.statusCanceled)
            Button { editingEntry = entry } label: { Label("Edit", systemImage: "pencil") }
                .tint(app.accentColor)
        }
    }

    private func headingRow(_ h: Heading) -> some View {
        HStack(spacing: 8) {
            Text(h.title.isEmpty ? String(localized: "Untitled") : h.title)
                .appFont(15, .semibold)
                .foregroundStyle(Theme.label(0.85))
                .lineLimit(1)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .contentShape(.rect)
        .onTapGesture {
            headingTitle = h.title
            renamingHeading = h
            showHeadingEditor = true
        }
        .contextMenu {
            Button { moveHeading(h, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(!canMoveHeading(h, by: -1))
            Button { moveHeading(h, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(!canMoveHeading(h, by: 1))
            Divider()
            Button(role: .destructive) { pendingDeleteHeading = h } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func insets(for row: Row) -> EdgeInsets {
        switch row {
        case .month: return EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16)
        case .heading: return EdgeInsets(top: 12, leading: 16, bottom: 2, trailing: 16)
        case .client: return EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
        case .composer: return EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16)
        case .entry: return EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        }
    }

    // MARK: Bottom toolbar

    /// More (leading) and Add (trailing) use the bottom bar's native edge
    /// positions. Each menu owns one 52-point circular Liquid Glass surface;
    /// the toolbar's automatic shared background is suppressed so it never
    /// becomes a button inside another button.
    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        if !isSearching {
            ToolbarItem(placement: .bottomBar) {
                moreMenu
                    .padding(.bottom, 10)
            }
                .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                addMenu
                    .padding(.bottom, 10)
            }
                .sharedBackgroundVisibility(.hidden)
        }
    }

    /// Trailing "+" — create actions only.
    private var addMenu: some View {
        Menu {
            if clients.isEmpty {
                Button { showNewClient = true } label: { MenuRowLabel("Income", glyph: "dollarsign") }
            } else {
                Menu {
                    ForEach(clients) { client in
                        Button { openComposer(for: client, month: app.displayedMonth) } label: { Text(client.name) }
                    }
                } label: {
                    MenuRowLabel("Income", glyph: "dollarsign")
                }
            }
            Button { showNewClient = true } label: { MenuRowLabel("Client", glyph: "person.crop.circle.badge.plus") }
            Button { startNewHeading() } label: { MenuRowLabel("Heading", glyph: "text.alignleft") }
            if !clients.isEmpty {
                Button { showPaste = true } label: { MenuRowLabel("Paste lines", glyph: "doc.on.clipboard") }
            }
        } label: {
            toolbarMenuSymbol("plus")
        }
        .tint(.primary)
        .accessibilityLabel("Add")
        .accessibilityIdentifier("ledger.fab")
    }

    /// Leading "…" — navigation, Search, and Settings live behind one clear
    /// overflow menu so the resting toolbar remains a two-action surface.
    private var moreMenu: some View {
        Menu {
            Button { isSearching = true } label: { MenuRowLabel("Search", glyph: "magnifyingglass") }
            Button { showInsights = true } label: { MenuRowLabel("Insights", glyph: "chart.bar") }
            Button { showPending = true } label: { MenuRowLabel(verbatim: pendingLabel, glyph: "clock") }
            Button { app.showSettings = true } label: { MenuRowLabel("Settings", glyph: "gearshape") }
        } label: {
            toolbarMenuSymbol("ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel("More")
        .accessibilityValue(pendingLabel)
        .accessibilityIdentifier("ledger.menu")
    }

    private func toolbarMenuSymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Theme.label)
            .frame(width: 52, height: 52)
            .contentShape(.circle)
            .glassEffect(.regular.tint(Theme.surface).interactive(), in: .circle)
    }

    /// "Pending" with the outstanding count folded into the title, since a
    /// plain system menu row can't carry a separate badge overlay.
    private var pendingLabel: String {
        let count = app.pendingEntries(clients).count
        return count > 0 ? String(localized: "Pending (\(count))") : String(localized: "Pending")
    }

    // MARK: Heading editor (compact card sheet, replaces the old text alert)

    /// Compact form sheet on the system header template: an inline navigation
    /// title with the system `Button(role: .close)`, the field in a white
    /// card, one pill CTA. Deleting an existing heading is the red trash in
    /// the leading toolbar slot.
    private var headingEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ChromeCard {
                    ChromeRow(icon: "text.alignleft") {
                        TextField("Title", text: $headingTitle)
                            .focused($headingFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(saveHeading)
                            .appFont(17)
                    }
                }

                PillCTA("Save",
                        isEnabled: !Validation.trimmed(headingTitle, max: Limits.maxHeadingLength).isEmpty,
                        action: saveHeading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle("Heading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if renamingHeading != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { confirmEditorHeadingDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .tint(Theme.statusCanceled)
                        .accessibilityLabel("Delete")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { showHeadingEditor = false }
                        .tint(.primary)
                }
            }
            // Same confirm-before-destroy contract as entry and client deletes.
            .alert("Delete heading?", isPresented: $confirmEditorHeadingDelete) {
                Button("Delete", role: .destructive, action: deleteRenamingHeading)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let heading = renamingHeading {
                    Text(heading.title.isEmpty ? String(localized: "Untitled") : heading.title)
                }
            }
        }
        // The compact card height can't hold accessibility-size text.
        .presentationDetents(typeSize.isAccessibilitySize ? [.medium] : [.height(240)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .task {
            // Focus once the sheet has settled.
            try? await Task.sleep(for: .milliseconds(400))
            headingFieldFocused = true
        }
    }

    // MARK: Entry actions

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) { e.status = s; e.markDirty() }
        if saveChanges() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func delete(_ e: Entry) {
        saveError = app.delete(e, context: context)
        if saveError == nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Add income

    private func toggleComposer(_ client: Client, month: Date) {
        let m = DateFormat.monthStart(of: month)
        withAnimation(.smooth(duration: 0.3)) {
            if activeComposerClient?.id == client.id, isComposerMonth(m) {
                composerClient = nil
            } else {
                composerClient = client
                composerMonth = m
            }
        }
    }

    private func openComposer(for client: Client, month: Date) {
        withAnimation(.smooth(duration: 0.3)) {
            composerClient = client
            composerMonth = DateFormat.monthStart(of: month)
        }
    }

    private func newProject() {
        if clients.isEmpty { showNewClient = true; return }
        if let c = mostRecentClient { openComposer(for: c, month: app.displayedMonth) }
    }

    private func startFirstLine() {
        if clients.isEmpty { showNewClient = true } else { newProject() }
    }

    private var mostRecentClient: Client? {
        clients.max { $0.createdAt < $1.createdAt } ?? clients.first
    }

    /// Launch-argument hooks for UI automation: each opens one surface
    /// directly so visual checks don't depend on scripted taps.
    private func runDemoIfNeeded() {
        guard !didRunDemo else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoComposer") {
            didRunDemo = true
            composerClient = clients.first
        } else if args.contains("-demoSettings") || args.contains("-demoDeveloperSettings") {
            didRunDemo = true
            app.showSettings = true
        } else if args.contains("-demoHeadingEditor") {
            didRunDemo = true
            showHeadingEditor = true
        } else if args.contains("-demoEdit") {
            didRunDemo = true
            editingEntry = clients.first(where: { !$0.entries.isEmpty })?.entries.first
        } else if args.contains("-demoSearch") {
            didRunDemo = true
            isSearching = true
        }
    }

    // MARK: Headings

    private func startNewHeading() {
        renamingHeading = nil
        headingTitle = ""
        showHeadingEditor = true
    }

    private func saveHeading() {
        let title = Validation.trimmed(headingTitle, max: Limits.maxHeadingLength)
        guard !title.isEmpty else { return }
        if let heading = renamingHeading {
            heading.title = title
            heading.markDirty()
        } else {
            context.insert(Heading(title: title,
                                   date: app.displayedMonth,
                                   sortIndex: nextHeadingSortIndex(in: app.displayedMonth)))
        }
        if saveChanges() {
            renamingHeading = nil
            showHeadingEditor = false
        }
    }

    private func deleteRenamingHeading() {
        if let h = renamingHeading { delete(h) }
        renamingHeading = nil
        showHeadingEditor = false
    }

    private func delete(_ h: Heading) {
        let snapshot = UndoableDelete.heading(HeadingSnapshot(h))
        SyncDeleteQueue.enqueue(.heading, id: h.id, in: context)
        withAnimation(.snappy) { context.delete(h) }
        if saveChanges() { app.stageUndo(snapshot) }
    }

    // The heading actions below run one-off (a tap, not a render), so building
    // a fresh snapshot per call is fine — it keeps their block ordering
    // identical to what the list displays.

    private func nextHeadingSortIndex(in month: Date) -> Int {
        (blocks(in: month, snapshot: app.insights.ledgerSnapshot(clients)).map(\.sortIndex).max() ?? -1) + 1
    }

    /// Whether the heading has a neighbouring block to trade places with in
    /// the given direction (-1 up, +1 down).
    private func canMoveHeading(_ h: Heading, by offset: Int) -> Bool {
        let ordered = blocks(in: DateFormat.monthStart(of: h.date),
                             snapshot: app.insights.ledgerSnapshot(clients))
        guard let idx = ordered.firstIndex(where: { $0.id == "h-\(h.id)" }) else { return false }
        return ordered.indices.contains(idx + offset)
    }

    /// Reorders a heading among its month's blocks by swapping sort indices with
    /// the adjacent block. Only the two swapped blocks are touched, so the rest
    /// of the ledger's order is left intact.
    private func moveHeading(_ h: Heading, by offset: Int) {
        let ordered = blocks(in: DateFormat.monthStart(of: h.date),
                             snapshot: app.insights.ledgerSnapshot(clients))
        guard let idx = ordered.firstIndex(where: { $0.id == "h-\(h.id)" }) else { return }
        let target = idx + offset
        guard ordered.indices.contains(target) else { return }

        let indices = ordered.map(\.sortIndex)
        var reordered = ordered
        reordered.swapAt(idx, target)
        withAnimation(.snappy) {
            for (position, block) in reordered.enumerated() where block.sortIndex != indices[position] {
                block.applySortIndex(indices[position])
            }
        }
        if saveChanges() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        saveError = app.save(context)
        return saveError == nil
    }

    // MARK: Month tracking

    private func updateDisplayedMonth(_ anchors: [MonthAnchor]) {
        guard !anchors.isEmpty else { return }
        let above = anchors.filter { $0.y <= 44 }
        let chosen = above.max(by: { $0.y < $1.y }) ?? anchors.min(by: { $0.y < $1.y })
        if let m = chosen?.month, !Calendar.current.isDate(m, equalTo: app.displayedMonth, toGranularity: .month) {
            app.displayedMonth = m
        }
    }

    private func isComposerMonth(_ month: Date) -> Bool {
        Calendar.current.isDate(month, equalTo: composerMonth, toGranularity: .month)
    }
}

// MARK: - Row model

private enum Row: Identifiable {
    /// Month and client rows carry their earned total, computed once in the
    /// snapshot pass — a row must never re-derive it by walking entries.
    case month(Date, Decimal)
    case heading(Heading)
    case client(Client, Date, Decimal)
    case composer(Client)
    case entry(Entry)

    var id: String {
        switch self {
        case .month(let d, _): return "m-\(d.timeIntervalSinceReferenceDate)"
        case .heading(let h): return "h-\(h.id)"
        case .client(let c, let d, _): return "c-\(c.id)-\(d.timeIntervalSinceReferenceDate)"
        case .composer(let c): return "composer-\(c.id)"
        case .entry(let e): return "e-\(e.id)"
        }
    }

    /// Whether the wrapped model was deleted out from under the row (see
    /// `rowView`). Only registration metadata is read, which stays safe on an
    /// invalidated model.
    var isInvalidated: Bool {
        switch self {
        case .month: return false
        case .heading(let h): return h.isInvalidated
        case .client(let c, _, _): return c.isInvalidated
        case .composer(let c): return c.isInvalidated
        case .entry(let e): return e.isInvalidated
        }
    }
}

private enum Block: Identifiable {
    case heading(Heading)
    case client(Client)

    var id: String {
        switch self {
        case .heading(let h): return "h-\(h.id)"
        case .client(let c): return "c-\(c.id)"
        }
    }

    var sortIndex: Int {
        switch self {
        case .heading(let h): return h.sortIndex
        case .client(let c): return c.sortIndex
        }
    }

    var createdAt: Date {
        switch self {
        case .heading(let h): return h.createdAt
        case .client(let c): return c.createdAt
        }
    }

    /// Writes a new sort index onto the wrapped model and flags it for sync.
    func applySortIndex(_ index: Int) {
        switch self {
        case .heading(let h): h.sortIndex = index; h.markDirty()
        case .client(let c): c.sortIndex = index; c.markDirty()
        }
    }

    func isOrderedBefore(_ other: Block) -> Bool {
        if sortIndex == other.sortIndex {
            return createdAt < other.createdAt
        }
        return sortIndex < other.sortIndex
    }
}

struct MonthAnchor: Equatable {
    let month: Date
    let y: CGFloat
}

struct MonthAnchorKey: PreferenceKey {
    static let defaultValue: [MonthAnchor] = []
    static func reduce(value: inout [MonthAnchor], nextValue: () -> [MonthAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Summary header

/// The floating summary cards, split out from `LedgerView` so that scrolling —
/// which retitles the header as the top month changes — only invalidates this
/// small view. It owns the `displayedMonth` read and derives the earned total
/// and six-month trend from it, keeping that dependency off the row list.
///
/// In search mode the full two-card header collapses to a slim glass bar so
/// the top chrome stays visible without covering results.
private struct LedgerSummaryHeader: View {
    @Environment(AppModel.self) private var app
    /// Earned totals per month key from the shared `LedgerSnapshot` pass.
    /// A month crossing during scroll used to recompute the displayed total
    /// and six-month trend as seven full sweeps over every entry; with the
    /// totals handed in, the crossing costs seven dictionary lookups.
    let monthlyTotals: [Int: Decimal]
    var isSearching: Bool = false
    var searchHitCount: Int = 0
    var searchEarnedTotal: Decimal = 0
    var hasSearchQuery: Bool = false
    let onOpenStats: () -> Void

    private var displayedTotal: Decimal {
        monthlyTotals[Insights.monthKey(of: app.displayedMonth)] ?? .zero
    }

    /// Earned totals for the six months ending at the displayed month, oldest
    /// first — feeds the Stats card's sparkline and its growth figure.
    private var displayedTrend: [Decimal] {
        let calendar = Calendar.current
        return (0..<6).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: app.displayedMonth)
                .map { monthlyTotals[Insights.monthKey(of: $0)] ?? .zero }
        }
    }

    var body: some View {
        Group {
            if isSearching {
                compactSearchHeader
            } else {
                SummaryCards(month: app.displayedMonth,
                             total: displayedTotal,
                             trend: displayedTrend,
                             onOpenStats: onOpenStats)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: app.displayedMonth)
        .animation(.snappy, value: isSearching)
    }

    /// Slim single glass bar: month + earned on the left; hit count / earned
    /// total of matches on the right once the query is non-empty.
    private var compactSearchHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormat.month(app.displayedMonth))
                    .appFont(13, .medium)
                    .foregroundStyle(Theme.label(0.55))
                Text(app.primaryString(displayedTotal))
                    .appFont(17, .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            if hasSearchQuery {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("^[\(searchHitCount) result](inflect: true)")
                        .appFont(13, .medium)
                        .foregroundStyle(Theme.label(0.55))
                    Text(app.primaryString(searchEarnedTotal))
                        .appFont(17, .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.summary))
        .accessibilityElement(children: .combine)
    }
}
