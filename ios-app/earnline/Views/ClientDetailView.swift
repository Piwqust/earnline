import SwiftUI
import SwiftData
import Charts

/// One client's compact profile: identity, three key figures, income trend,
/// and drill-down rows for statuses, projects, and the complete history.
/// Renaming, recoloring, and deletion stay behind the toolbar edit action.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    let client: Client

    @State private var showEditSheet = false
    /// Scrub position on the earnings chart; snapped to the plotted month.
    @State private var chartSelection: Date?
    @State private var snapshot: ClientDetailSnapshot?
    @State private var snapshotError: String?
    @State private var dataRevision = 0

    private var calendar: Calendar { .current }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 170
    }

    private struct SnapshotRevision: Hashable {
        let baseCurrencyCode: String
        let secondaryCurrencyCode: String
        let rate: Double
        let dataRevision: Int
    }

    private var snapshotRevision: SnapshotRevision {
        SnapshotRevision(
            baseCurrencyCode: app.baseCurrencyCode,
            secondaryCurrencyCode: app.secondaryCurrencyCode,
            rate: app.rate,
            dataRevision: dataRevision
        )
    }

    var body: some View {
        // A sync pull can delete this client while its page is open; reading
        // the invalidated model would trap, so show the standard empty state
        // until navigation pops the destination.
        if client.isInvalidated {
            Theme.background.ignoresSafeArea()
        } else {
            detailBody
        }
    }

    private var detailBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                profileSummary(snapshot)
                if let snapshot {
                    trendCard(snapshot.months)
                    statusCard(snapshot.statusTotals)

                    if !snapshot.projectTotals.isEmpty {
                        section("By project") { projectsCard(snapshot.projectTotals) }
                    }

                    allTransactionsCard(snapshot.transactionCount)
                } else if snapshotError == nil {
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .accessibilityIdentifier("client.profileLoading")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .accessibilityIdentifier("client.profile")
        }
        .background(Theme.background)
        .navigationTitle("Client Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                // Figma draws the edit glyph in the primary label ink, not the
                // app accent — black in light mode, white in dark — matching
                // the back chevron beside it rather than standing out in blue.
                .tint(.primary)
                .accessibilityLabel("Edit client")
                .accessibilityIdentifier("client.edit")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditClientSheet(
                client: client,
                otherClientNames: clients.filter { $0.id != client.id }.map(\.name),
                onDelete: deleteClient
            )
        }
        .undoToastHost()
        .task(id: snapshotRevision) {
            await loadSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            dataRevision &+= 1
        }
        .saveErrorAlert($snapshotError)
    }

    // MARK: Profile summary

    private func profileSummary(_ snapshot: ClientDetailSnapshot?) -> some View {
        VStack(spacing: 40) {
            Text(client.name)
                .appFont(24, .semibold, relativeTo: .title2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .glassEffect(
                    .regular.tint(Color(hex: client.colorHex)).interactive(),
                    in: .capsule
                )
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 4) {
                moneySummaryStat("Total earned", value: snapshot?.total)
                moneySummaryStat("Avg / month", value: snapshot?.averagePerActiveMonth.rounded())
                summaryStat("Share of income", value: shareOfIncomeString(snapshot?.shareOfIncome))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 4)
    }

    private func moneySummaryStat(_ title: LocalizedStringKey, value: Decimal?) -> some View {
        VStack(spacing: 2) {
            summaryLabel(title)
            if let value {
                MoneyAmountText(
                    baseAmount: value,
                    size: 24,
                    weight: .bold,
                    design: .rounded,
                    relativeTo: .title2,
                    color: Theme.label,
                    minimumScaleFactor: 0.55
                )
                .animation(.snappy(duration: 0.3), value: value)
            } else {
                Text("—")
                    .appFont(24, .bold, design: .rounded, relativeTo: .title2)
                    .foregroundStyle(Theme.label(0.25))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func summaryStat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 2) {
            summaryLabel(title)
            Text(value)
                .appFont(24, .bold, design: .rounded, relativeTo: .title2)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func summaryLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .appFont(13, .medium, relativeTo: .footnote)
            .foregroundStyle(Theme.label(0.5))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
    }

    // MARK: Sections

    private func section(_ title: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title)
            content()
        }
    }

    // MARK: Earnings chart — 12 months of this client, scrubbable

    private func trendCard(_ data: [ClientDetailSnapshot.MonthPoint]) -> some View {
        let selected = chartSelection.flatMap { selection in
            data.first { calendar.isDate($0.month, equalTo: selection, toGranularity: .month) }
        }
        let hasData = data.contains { $0.total > 0 }
        let lineColor = Color(hex: client.colorHex)
        let highlighted = selected ?? data.last
        return ChromeCard {
            Chart {
                ForEach(data, id: \.month) { point in
                    AreaMark(
                        x: .value("Month", point.month, unit: .month),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Earned", doubleValue(point.total))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [lineColor.opacity(0.22), lineColor.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Earned", doubleValue(point.total))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                if let selected {
                    RuleMark(x: .value("Month", selected.month, unit: .month))
                        .foregroundStyle(Theme.label(0.14))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            chartCallout(selected)
                        }
                }

                if let highlighted {
                    PointMark(
                        x: .value("Highlighted month", highlighted.month, unit: .month),
                        y: .value("Highlighted earnings", doubleValue(highlighted.total))
                    )
                    .foregroundStyle(lineColor)
                    .symbolSize(55)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactAmount(amount))
                                .font(.caption2)
                                .foregroundStyle(Theme.label(0.4))
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartXSelection(value: $chartSelection)
            .frame(height: chartHeight)
            .padding(.leading, 0)
            .padding(.trailing, 10)
            .padding(.vertical, 14)
            .overlay {
                if !hasData {
                    Text("No earned income in the last year")
                        .appFont(11)
                        .foregroundStyle(Theme.label(0.4))
                }
            }
        }
    }

    private func chartCallout(_ point: ClientDetailSnapshot.MonthPoint) -> some View {
        VStack(spacing: 1) {
            Text(app.primaryString(point.total))
                .appFont(12, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
            Text(DateFormat.monthAndYear(point.month))
                .appFont(9)
                .foregroundStyle(Theme.label(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface, in: .rect(cornerRadius: 8))
        .shadow(color: Theme.label(0.12), radius: 6, y: 2)
    }

    /// This client's slice of everything ever earned, e.g. "37%".
    private func shareOfIncomeString(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((min(fraction, 9.99) * 100).rounded()))%"
    }

    // MARK: Status & project breakdowns

    private func statusCard(_ totals: [ClientDetailSnapshot.StatusTotal]) -> some View {
        ChromeCard {
            ForEach(totals) { total in
                let status = EntryStatus.fromSyncRawValue(total.statusRaw)
                NavigationLink {
                    ClientTransactionsView(
                        title: status.title,
                        clientID: client.id,
                        filter: .status(status.rawValue)
                    )
                } label: {
                    ChromeRow(icon: nil) {
                        Image(systemName: status.symbol)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(status.tint)
                            .frame(width: 14)
                        Text(status.title).foregroundStyle(Theme.label)
                        Spacer()
                        Text("\(total.count)")
                            .foregroundStyle(Theme.label(0.4)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(app.primaryString(total.total))
                            .foregroundStyle(Theme.label)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.label(0.25))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.3), value: total.total)
                if total.id != totals.last?.id {
                    ChromeDivider(inset: 44)
                }
            }
        }
    }

    private func projectsCard(_ totals: [ClientDetailSnapshot.ProjectTotal]) -> some View {
        ChromeCard {
            ForEach(Array(totals.enumerated()), id: \.element.id) { index, total in
                NavigationLink {
                    ClientTransactionsView(
                        title: total.name,
                        clientID: client.id,
                        filter: .project(total.name)
                    )
                } label: {
                    ChromeRow(icon: nil) {
                        Text(total.name).foregroundStyle(Theme.label).lineLimit(1)
                        Spacer()
                        Text("\(total.count)")
                            .foregroundStyle(Theme.label(0.4))
                            .monospacedDigit()
                        Text(app.primaryString(total.total))
                            .foregroundStyle(Theme.label)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.label(0.25))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.3), value: total.total)
                if index < totals.count - 1 {
                    ChromeDivider(inset: 16)
                }
            }
        }
    }

    private func allTransactionsCard(_ count: Int) -> some View {
        ChromeCard {
            NavigationLink {
                ClientTransactionsView(
                    title: String(localized: "All Transactions"),
                    clientID: client.id,
                    filter: .all
                )
            } label: {
                ChromeRow(icon: nil) {
                    Text("All Transactions")
                        .foregroundStyle(Theme.label)
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(Theme.label(0.4))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.label(0.25))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func loadSnapshot() async {
        snapshotError = nil
        let loader = ClientDetailSnapshotLoader(modelContainer: context.container)
        do {
            let loaded = try await loader.load(clientID: client.id, converter: app.converter)
            guard !Task.isCancelled else { return }
            snapshot = loaded
        } catch is CancellationError {
            return
        } catch {
            snapshotError = error.localizedDescription
        }
    }

    private func deleteClient() {
        let target = client
        let snapshot = UndoableDelete.client(ClientSnapshot(target))
        let app = app
        let context = context
        dismiss()
        // Delete after the pop so nothing in this hierarchy renders a dead model.
        Task { @MainActor in
            SyncDeleteQueue.enqueue(.client, id: target.id, in: context)
            context.delete(target)
            // Same save + sync + undo contract as AppModel.delete: the undo
            // toast is only staged once the delete actually persisted —
            // offering to restore a delete that failed would undo nothing.
            if app.save(context) == nil {
                // Staged after the pop: the toast shows on the ledger underneath.
                app.stageUndo(snapshot)
            } else {
                context.rollback()
            }
        }
    }

    // MARK: Helpers

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Compact axis label ("2k", "1.5M") — earned values are never negative here.
    private func compactAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return "\(CurrencyFormatter.grouped(Decimal(value / 1_000_000), code: app.baseCurrencyCode))M"
        }
        if value >= 1000 {
            return "\(CurrencyFormatter.grouped(Decimal(value / 1000), code: app.baseCurrencyCode))k"
        }
        return CurrencyFormatter.grouped(Decimal(value), code: app.baseCurrencyCode)
    }
}

/// A focused drill-down used by status, project, and all-transactions rows.
/// It keeps the ledger's existing edit, status, delete, undo, and save-error
/// behavior instead of turning the summary page into another long ledger.
private struct ClientTransactionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    enum Filter {
        case all
        case status(String)
        case project(String)
    }

    let title: String
    let filter: Filter
    @Query private var entries: [Entry]

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var saveError: String?

    init(title: String, clientID: UUID, filter: Filter) {
        self.title = title
        self.filter = filter
        let targetID = clientID
        _entries = Query(
            filter: #Predicate<Entry> { entry in
                entry.client?.id == targetID
            },
            sort: [SortDescriptor(\Entry.date, order: .reverse)]
        )
    }

    private var liveEntries: [Entry] {
        entries
            .filter { !$0.isInvalidated && !$0.isDeleted }
            .filter { entry in
                switch filter {
                case .all:
                    return true
                case .status(let rawValue):
                    return entry.statusRaw == rawValue
                        || (rawValue == EntryStatus.paid.rawValue && entry.statusRaw == "logged")
                case .project(let name):
                    return (entry.project?.isEmpty == false ? entry.project! : "—") == name
                }
            }
    }

    private var sections: [(month: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: liveEntries) {
            calendar.date(
                from: calendar.dateComponents([.year, .month], from: $0.date)
            ) ?? $0.date
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        Group {
            if liveEntries.isEmpty {
                ContentUnavailableView(
                    "No transactions",
                    systemImage: "tray",
                    description: Text("Transactions matching this group will appear here.")
                )
            } else {
                List {
                    ForEach(sections, id: \.month) { section in
                        Section {
                            ForEach(section.entries, id: \.id) { entry in
                                EntryRow(
                                    entry: entry,
                                    onSetStatus: { setStatus(entry, $0) },
                                    onEdit: { editingEntry = entry },
                                    onDelete: { pendingDelete = entry }
                                )
                                .padding(.vertical, 8)
                                .listRowInsets(
                                    EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
                                )
                                .listRowBackground(Theme.background)
                            }
                        } header: {
                            Text(DateFormat.monthAndYear(section.month))
                                .appFont(15, .medium)
                                .foregroundStyle(Theme.label(0.5))
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
        .alert(
            "Delete income line?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                saveError = app.delete(entry, context: context)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text("\(CurrencyFormatter.string(entry.amount, code: entry.currencyCode)) · \(entry.task)")
        }
        .saveErrorAlert($saveError)
        .undoToastHost()
    }

    private func setStatus(_ entry: Entry, _ status: EntryStatus) {
        withAnimation(.snappy) {
            entry.status = status
            entry.markDirty()
        }
        saveError = app.save(context)
    }
}
