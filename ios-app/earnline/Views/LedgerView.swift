import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Heading.sortIndex) private var headings: [Heading]

    @State private var composerClient: Client?
    @State private var showNewClient = false
    @State private var showPaste = false
    @State private var showSearch = false
    @State private var showInsights = false
    @State private var showPending = false
    @State private var showSettings = false
    @State private var detailClient: Client?
    @State private var editingEntry: Entry?
    @State private var renamingHeading: Heading?
    @State private var showHeadingEditor = false
    @State private var headingTitle = ""
    @State private var pendingDelete: Entry?
    @State private var didRunDemo = false
    @State private var saveError: String?

    // MARK: Derived

    private var months: [Date] { app.monthsWithData(clients) }

    private func sectionHeadings(in month: Date) -> [Heading] {
        headings.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private func sectionClients(in month: Date) -> [Client] {
        var list = app.clientsWithEntries(clients, in: month)
        if let cc = composerClient, isCurrentMonth(month), !list.contains(where: { $0.id == cc.id }) {
            list.append(cc)
        }
        return list
    }

    private func blocks(in month: Date) -> [Block] {
        let h = sectionHeadings(in: month).map { Block.heading($0) }
        let c = sectionClients(in: month).map { Block.client($0) }
        return (h + c).sorted { $0.isOrderedBefore($1) }
    }

    private var ledgerRows: [Row] {
        var rows: [Row] = []
        for month in months {
            rows.append(.month(month))
            for block in blocks(in: month) {
                switch block {
                case .heading(let h): rows.append(.heading(h))
                case .client(let c):
                    rows.append(.client(c, month))
                    if isCurrentMonth(month), composerClient?.id == c.id {
                        rows.append(.composer(c))
                    }
                    for e in app.entries(of: c, in: month) { rows.append(.entry(e)) }
                }
            }
        }
        return rows
    }

    private var hasContent: Bool {
        !headings.isEmpty || clients.contains { !$0.entries.isEmpty }
    }

    private var displayedTotal: Decimal { app.monthTotal(clients, in: app.displayedMonth) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.background.ignoresSafeArea()
                scrollContent
                fab
            }
            .navigationDestination(item: $detailClient) { ClientDetailView(client: $0) }
            .safeAreaInset(edge: .top) { header }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: runDemoIfNeeded)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
        .sheet(isPresented: $showNewClient) {
            NewClientSheet(existingClients: clients) { newClient in
                openComposer(for: newClient)
            }
        }
        .sheet(isPresented: $showPaste) {
            PasteLinesSheet(clients: clients, defaultClient: mostRecentClient)
        }
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showInsights) { InsightsView() }
        .sheet(isPresented: $showPending) { PendingView() }
        .alert("Heading", isPresented: Binding(
            get: { showHeadingEditor },
            set: {
                showHeadingEditor = $0
                if !$0 { renamingHeading = nil }
            }
        )) {
            TextField("Title", text: $headingTitle)
            Button("Save") { saveHeading() }
                .disabled(Validation.trimmed(headingTitle, max: Limits.maxHeadingLength).isEmpty)
            if renamingHeading != nil {
                Button("Delete", role: .destructive) { deleteRenamingHeading() }
            }
            Button("Cancel", role: .cancel) {
                renamingHeading = nil
                showHeadingEditor = false
            }
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
        .alert("Could not save changes", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Try again.")
        }
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        SummaryPill(month: app.displayedMonth, total: displayedTotal)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .contextMenu {
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            .animation(.snappy, value: app.displayedMonth)
    }

    // MARK: Scroll content (List → native swipe actions)

    private var scrollContent: some View {
        List {
            if !hasContent {
                EmptyStateView(onStart: startFirstLine)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } else {
                ForEach(ledgerRows) { row in
                    rowView(row)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(insets(for: row))
                }
            }
            Color.clear
                .frame(height: 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .coordinateSpace(name: "ledger")
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(MonthAnchorKey.self) { anchors in
            updateDisplayedMonth(anchors)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .month(let m):
            monthRow(m)
        case .heading(let h):
            headingRow(h)
        case .client(let c, let m):
            clientHeaderRow(c, month: m)
        case .composer(let c):
            composerRow(c)
        case .entry(let e):
            entryRow(e)
        }
    }

    private func clientHeaderRow(_ client: Client, month: Date) -> some View {
        ClientChip(
            client: client,
            total: app.total(of: client, in: month),
            onOpen: { detailClient = client },
            onAdd: { toggleComposer(client) }
        )
    }

    private func composerRow(_ client: Client) -> some View {
        SmartComposer(client: client)
            .transition(.opacity)
    }

    private func monthRow(_ month: Date) -> some View {
        MonthDivider(
            title: DateFormat.month(month),
            total: app.monthTotal(clients, in: month)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: MonthAnchorKey.self,
                    value: [MonthAnchor(month: month, y: geo.frame(in: .named("ledger")).minY)]
                )
            }
        )
    }

    private func entryRow(_ entry: Entry) -> some View {
        EntryRow(
            entry: entry,
            onSetStatus: { setStatus(entry, $0) },
            onEdit: { editingEntry = entry },
            onDelete: { pendingDelete = entry }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
            Button { editingEntry = entry } label: { Label("Edit", systemImage: "pencil") }
                .tint(Theme.blue)
        }
    }

    private func headingRow(_ h: Heading) -> some View {
        HStack(spacing: 8) {
            Text(h.title.isEmpty ? "Untitled" : h.title)
                .font(.system(size: 15, weight: .semibold))
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
            Button(role: .destructive) { delete(h) } label: { Label("Delete", systemImage: "trash") }
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

    // MARK: FAB

    private var fab: some View {
        Menu {
            if clients.isEmpty {
                Button { showNewClient = true } label: { Label("Income", systemImage: "dollarsign") }
            } else {
                Menu {
                    ForEach(clients) { client in
                        Button { openComposer(for: client) } label: { Text(client.name) }
                    }
                } label: {
                    Label("Income", systemImage: "dollarsign")
                }
            }
            Button { showNewClient = true } label: { Label("Client", systemImage: "person.crop.circle.badge.plus") }
            Button { startNewHeading() } label: { Label("Heading", systemImage: "text.alignleft") }
            if !clients.isEmpty {
                Button { showPaste = true } label: { Label("Paste lines", systemImage: "doc.on.clipboard") }
            }
            Divider()
            let pendingCount = app.pendingEntries(clients).count
            Button { showPending = true } label: {
                Label(pendingCount > 0 ? "Pending (\(pendingCount))" : "Pending", systemImage: "clock")
            }
            Button { showSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
            Button { showInsights = true } label: { Label("Insights", systemImage: "chart.bar") }
            Divider()
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Add")
        .accessibilityIdentifier("ledger.fab")
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    // MARK: Entry actions

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) { e.status = s; e.markDirty() }
        if saveChanges() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func delete(_ e: Entry) {
        SyncDeleteQueue.enqueue(.entry, id: e.id, in: context)
        withAnimation(.snappy) { context.delete(e) }
        if saveChanges() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Add income

    private func toggleComposer(_ client: Client) {
        withAnimation(.smooth(duration: 0.3)) {
            composerClient = (composerClient?.id == client.id) ? nil : client
        }
    }

    private func openComposer(for client: Client) {
        withAnimation(.smooth(duration: 0.3)) { composerClient = client }
    }

    private func newProject() {
        if clients.isEmpty { showNewClient = true; return }
        if let c = mostRecentClient { openComposer(for: c) }
    }

    private func startFirstLine() {
        if clients.isEmpty { showNewClient = true } else { newProject() }
    }

    private var mostRecentClient: Client? {
        clients.max { $0.createdAt < $1.createdAt } ?? clients.first
    }

    private func runDemoIfNeeded() {
        guard !didRunDemo else { return }
        guard ProcessInfo.processInfo.arguments.contains("-demoComposer") else { return }
        didRunDemo = true
        composerClient = clients.first
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
        SyncDeleteQueue.enqueue(.heading, id: h.id, in: context)
        withAnimation(.snappy) { context.delete(h) }
        _ = saveChanges()
    }

    private func nextHeadingSortIndex(in month: Date) -> Int {
        (blocks(in: month).map(\.sortIndex).max() ?? -1) + 1
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try context.save()
            app.queueSync(context: context)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
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

    private func isCurrentMonth(_ month: Date) -> Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }
}

// MARK: - Row model

private enum Row: Identifiable {
    case month(Date)
    case heading(Heading)
    case client(Client, Date)
    case composer(Client)
    case entry(Entry)

    var id: String {
        switch self {
        case .month(let d): return "m-\(d.timeIntervalSinceReferenceDate)"
        case .heading(let h): return "h-\(h.id)"
        case .client(let c, let d): return "c-\(c.id)-\(d.timeIntervalSinceReferenceDate)"
        case .composer(let c): return "composer-\(c.id)"
        case .entry(let e): return "e-\(e.id)"
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
