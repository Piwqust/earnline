import SwiftUI
import SwiftData

/// A focused drill-down used by status, project, and all-transactions rows.
/// It keeps the ledger's existing edit, status, delete, undo, and save-error
/// behavior instead of turning the summary page into another long ledger.
struct ClientTransactionsView: View {
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    enum Filter {
        case all
        /// A resolved status, not a raw column value: `Entry.status` already
        /// maps legacy raws (the old "logged") through
        /// `EntryStatus.fromSyncRawValue`, so matching on the enum keeps that
        /// mapping in one place instead of restating it here.
        case status(EntryStatus)
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
                    true
                case .status(let status):
                    entry.status == status
                case .project(let name):
                    (entry.project?.isEmpty == false ? entry.project! : "—") == name
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
                saveError = mutations.delete(entry, context: context)
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
        saveError = mutations.save(context)
    }
}
