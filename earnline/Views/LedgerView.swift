import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Heading.sortIndex) private var headings: [Heading]

    @State private var composerTarget: Client?
    @State private var showComposer = false
    @State private var showNewClient = false
    @State private var showSettings = false
    @State private var detailClient: Client?
    @State private var editingEntry: Entry?
    @State private var renamingHeading: Heading?
    @State private var headingTitle = ""
    @State private var composerInitialText = ""
    @State private var didRunDemo = false

    // MARK: Derived

    private var months: [Date] { app.monthsWithData(clients) }

    private func sectionClients(in month: Date) -> [Client] {
        var list = app.clientsWithEntries(clients, in: month)
        if showComposer, let t = composerTarget, isCurrentMonth(month),
           !list.contains(where: { $0.id == t.id }) {
            list.append(t)
        }
        return list
    }

    private func sectionHeadings(in month: Date) -> [Heading] {
        headings.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private func blocks(in month: Date) -> [Block] {
        let h = sectionHeadings(in: month).map { Block.heading($0) }
        let c = sectionClients(in: month).map { Block.client($0) }
        return (h + c).sorted { $0.order < $1.order }
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
            NewClientSheet(existingCount: clients.count) { newClient in
                composerTarget = newClient
                composerInitialText = ""
                withAnimation(.snappy) { showComposer = true }
            }
        }
        .alert("Heading", isPresented: Binding(
            get: { renamingHeading != nil },
            set: { if !$0 { renamingHeading = nil } }
        )) {
            TextField("Title", text: $headingTitle)
            Button("Save") { saveHeading() }
            Button("Delete", role: .destructive) { deleteRenamingHeading() }
            Button("Cancel", role: .cancel) { renamingHeading = nil }
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

    // MARK: Scroll content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !hasContent && !showComposer {
                    EmptyStateView(onStart: startFirstLine)
                        .padding(.top, 4)
                } else {
                    ForEach(months, id: \.self) { month in
                        monthSection(month)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16)
            .animation(.snappy(duration: 0.3), value: months)
            .animation(.snappy(duration: 0.3), value: showComposer)
        }
        .coordinateSpace(name: "ledger")
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(MonthAnchorKey.self) { anchors in
            updateDisplayedMonth(anchors)
        }
    }

    private func monthSection(_ month: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MonthDivider(
                title: DateFormat.month(month),
                total: app.primaryString(app.monthTotal(clients, in: month))
            )
            .padding(.top, 4)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: MonthAnchorKey.self,
                        value: [MonthAnchor(month: month, y: geo.frame(in: .named("ledger")).minY)]
                    )
                }
            )

            ForEach(blocks(in: month)) { block in
                switch block {
                case .heading(let h): headingRow(h)
                case .client(let c): clientSection(c, month: month)
                }
            }
        }
    }

    private func clientSection(_ client: Client, month: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ClientChip(
                client: client,
                total: app.total(of: client, in: month),
                onOpen: { detailClient = client },
                onAdd: { openComposer(for: client) }
            )

            if showComposer, composerTarget?.id == client.id, isCurrentMonth(month) {
                SmartComposer(
                    targetClient: $composerTarget,
                    initialText: composerInitialText,
                    onClose: closeComposer
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(app.entries(of: client, in: month)) { entry in
                    EntryRow(
                        entry: entry,
                        onSetStatus: { setStatus(entry, $0) },
                        onEdit: { editingEntry = entry },
                        onDelete: { delete(entry) }
                    )
                }
            }
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
        .padding(.top, 4)
        .contentShape(.rect)
        .onTapGesture {
            headingTitle = h.title
            renamingHeading = h
        }
        .contextMenu {
            Button(role: .destructive) { delete(h) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: FAB

    private var fab: some View {
        Menu {
            Button { addHeading() } label: { Label("New Heading", systemImage: "textformat") }
            Button { newProject() } label: { Label("New Project", systemImage: "folder") }
            Button { showNewClient = true } label: { Label("New Client", systemImage: "person.crop.circle") }
            Divider()
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    // MARK: Entry actions

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) {
            e.status = s
            e.markDirty()
        }
        try? context.save()
        app.queueSync(context: context)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func delete(_ e: Entry) {
        SyncDeleteQueue.enqueue(.entry, id: e.id, in: context)
        withAnimation(.snappy) { context.delete(e) }
        try? context.save()
        app.queueSync(context: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Composer actions

    private func openComposer(for client: Client) {
        if showComposer, composerTarget?.id == client.id {
            withAnimation(.snappy) { showComposer = false }
            return
        }
        composerInitialText = ""
        composerTarget = client
        withAnimation(.snappy) { showComposer = true }
    }

    private func closeComposer() {
        withAnimation(.snappy) { showComposer = false }
    }

    private func newProject() {
        if clients.isEmpty { showNewClient = true; return }
        composerInitialText = ""
        composerTarget = mostRecentClient
        withAnimation(.snappy) { showComposer = true }
    }

    private func startFirstLine() {
        if clients.isEmpty { showNewClient = true } else { newProject() }
    }

    private var mostRecentClient: Client? {
        clients.max { $0.createdAt < $1.createdAt } ?? clients.first
    }

    private func runDemoIfNeeded() {
        guard !didRunDemo, ProcessInfo.processInfo.arguments.contains("-demoComposer") else { return }
        didRunDemo = true
        composerInitialText = "$320 LunaAI: Mobile onboarding flow  hold until 18.07.26"
        composerTarget = clients.first
        withAnimation(.snappy) { showComposer = true }
    }

    // MARK: Headings

    private func addHeading() {
        let next = (headings.map(\.sortIndex).max() ?? 0) + 1
        let heading = Heading(title: "", date: .now, sortIndex: next)
        context.insert(heading)
        try? context.save()
        app.queueSync(context: context)
        headingTitle = ""
        renamingHeading = heading
    }

    private func saveHeading() {
        renamingHeading?.title = Validation.trimmed(headingTitle, max: Limits.maxHeadingLength)
        renamingHeading?.markDirty()
        try? context.save()
        app.queueSync(context: context)
        renamingHeading = nil
    }

    private func deleteRenamingHeading() {
        if let h = renamingHeading { delete(h) }
        renamingHeading = nil
    }

    private func delete(_ h: Heading) {
        SyncDeleteQueue.enqueue(.heading, id: h.id, in: context)
        withAnimation(.snappy) { context.delete(h) }
        try? context.save()
        app.queueSync(context: context)
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

// MARK: - Block & scroll anchor

private enum Block: Identifiable {
    case heading(Heading)
    case client(Client)

    var id: String {
        switch self {
        case .heading(let h): return "h-\(h.id)"
        case .client(let c): return "c-\(c.id)"
        }
    }

    var order: Date {
        switch self {
        case .heading(let h): return h.createdAt
        case .client(let c): return c.createdAt
        }
    }
}

struct MonthAnchor: Equatable {
    let month: Date
    let y: CGFloat
}

struct MonthAnchorKey: PreferenceKey {
    static var defaultValue: [MonthAnchor] = []
    static func reduce(value: inout [MonthAnchor], nextValue: () -> [MonthAnchor]) {
        value.append(contentsOf: nextValue())
    }
}
