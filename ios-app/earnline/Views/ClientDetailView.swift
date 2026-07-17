import SwiftUI
import SwiftData

/// One client's compact profile: identity, three key figures, income trend,
/// and drill-down rows for statuses, projects, and the complete history.
/// Renaming, recoloring, and deletion stay behind the toolbar edit action.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \ProjectIconPreference.projectKey) private var projectIconPreferences: [ProjectIconPreference]
    let client: Client
    /// Internal-only gate for the noninteractive account tour. It delays the
    /// presentation of an already loaded real snapshot by a beat; production
    /// callers leave it nil and keep the current loading behaviour.
    var previewHistoryIsLoaded: Bool? = nil
    /// Internal-only timing for the account tour's client-history appearance.
    /// Production callers leave this nil and keep the existing static render.
    var previewHistoryFadeDuration: TimeInterval? = nil

    @State private var showEditSheet = false
    @State private var snapshot: ClientDetailSnapshot?
    @State private var snapshotError: String?
    @State private var dataRevision = 0
    @State private var rendersAchievementPreview = true

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
                Group {
                    if let snapshot, previewHistoryIsLoaded != false {
                        if app.clientBadgesEnabled {
                            section("Achievements") { achievementsCard(snapshot.achievements) }
                        }
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
                .transition(.opacity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .accessibilityIdentifier("client.profile")
            .animation(
                previewHistoryFadeDuration.map { .easeInOut(duration: $0) },
                value: previewHistoryIsLoaded
            )
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
        .onAppear { rendersAchievementPreview = true }
        .onDisappear { rendersAchievementPreview = false }
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
                    .foregroundStyle(.tertiary)
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
            .foregroundStyle(.secondary)
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

    // MARK: Achievements

    private func achievementsCard(_ achievements: [ClientAchievement]) -> some View {
        let earnedCount = achievements.count(where: \.isUnlocked)
        return ChromeCard {
            NavigationLink {
                ClientBadgesView(clientName: client.name, achievements: achievements)
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(earnedCount) of \(achievements.count) earned")
                            .appFont(14, .medium, relativeTo: .subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        ForEach(Array(achievements.prefix(3))) { achievement in
                            Group {
                                if rendersAchievementPreview {
                                    ClientBadgeModelView(achievement: achievement)
                                } else {
                                    Color.clear
                                }
                            }
                                .frame(maxWidth: .infinity)
                                .frame(height: dynamicTypeSize.isAccessibilitySize ? 104 : 84)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Achievements")
                .accessibilityValue("\(earnedCount) of \(achievements.count) earned")
                .accessibilityHint("Open the 3D award collection")
                .accessibilityIdentifier("client.achievements.open")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Earnings chart — 12 months of this client, scrubbable

    private func trendCard(_ data: [ClientDetailSnapshot.MonthPoint]) -> some View {
        EarningsChartCard(
            points: data.enumerated().map { index, point in
                .init(month: point.month,
                      total: point.total,
                      previousTotal: index > 0 ? data[index - 1].total : nil)
            },
            tint: Color(hex: client.colorHex),
            emptyText: "No earned income in the last year"
        )
        .accessibilityIdentifier("client.earningsChart")
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
                            .foregroundStyle(.tertiary).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(app.primaryString(total.total))
                            .foregroundStyle(Theme.label)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
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
                        Image(systemName: projectSymbol(for: total.name).systemImageName)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(total.name).foregroundStyle(Theme.label).lineLimit(1)
                        Spacer()
                        Text("\(total.count)")
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(app.primaryString(total.total))
                            .foregroundStyle(Theme.label)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
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

    private func projectSymbol(for projectName: String) -> ProjectSymbol {
        ProjectIconResolver.symbol(for: projectName, in: projectIconPreferences)
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
                                .foregroundStyle(.secondary)
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
