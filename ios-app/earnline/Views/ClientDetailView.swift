import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Bindable var client: Client

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var saveError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private var sortedEntries: [Entry] { client.entries.sorted { $0.date > $1.date } }

    private var totalAll: Decimal {
        client.entries
            .filter { $0.status.isIncludedInEarnedTotals }
            .reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }
    private func statusTotal(_ s: EntryStatus) -> (count: Int, sum: Decimal) {
        let items = client.entries.filter { $0.status == s }
        return (items.count, items.reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) })
    }
    private var projectTotals: [(name: String, sum: Decimal)] {
        var dict: [String: Decimal] = [:]
        for e in client.entries where e.status.isIncludedInEarnedTotals {
            let key = (e.project?.isEmpty == false ? e.project! : "—")
            dict[key, default: 0] += app.toBase(e.amount, code: e.currencyCode)
        }
        return dict.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Text(client.name)
                        .font(.chipName)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.tint(Color(hex: client.colorHex)), in: .capsule)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        MoneyAmountText(baseAmount: totalAll,
                                        font: .system(size: 20, weight: .semibold),
                                        color: Theme.label)
                    }
                    .animation(.snappy(duration: 0.3), value: totalAll)
                }
                .listRowBackground(Color.clear)
            }

            Section("By status") {
                ForEach(EntryStatus.allCases) { s in
                    let t = statusTotal(s)
                    HStack {
                        Image(systemName: s.symbol).foregroundStyle(s.tint)
                        Text(s.title)
                        Spacer()
                        Text("\(t.count)")
                            .foregroundStyle(Theme.label(0.4)).monospacedDigit()
                            .contentTransition(.numericText())
                        MoneyAmountText(baseAmount: t.sum,
                                        font: .body,
                                        color: Theme.label(0.7))
                    }
                    .animation(.snappy(duration: 0.3), value: t.sum)
                }
            }

            if projectTotals.count > 1 || (projectTotals.first?.name ?? "—") != "—" {
                Section("By project") {
                    ForEach(projectTotals, id: \.name) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            MoneyAmountText(baseAmount: p.sum,
                                            font: .body,
                                            color: Theme.label(0.7))
                                .animation(.snappy(duration: 0.3), value: p.sum)
                        }
                    }
                }
            }

            Section("Lines") {
                ForEach(sortedEntries) { entry in
                    EntryRow(
                        entry: entry,
                        onSetStatus: { setStatus(entry, $0) },
                        onEdit: { editingEntry = entry },
                        onDelete: { pendingDelete = entry }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
            }

            Section("Edit") {
                TextField("Name", text: $client.name)
                    .onChange(of: client.name) { _, v in
                        client.name = Validation.capped(v, max: Limits.maxClientNameLength)
                        client.markDirty()
                        _ = saveChanges()
                    }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Theme.clientPalette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(height: 30)
                            .overlay { if hex == client.colorHex { Circle().strokeBorder(.white, lineWidth: 2).padding(2) } }
                            .overlay { Circle().strokeBorder(Theme.label(0.08), lineWidth: 0.5) }
                            .onTapGesture {
                                client.colorHex = hex
                                client.markDirty()
                                _ = saveChanges()
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
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
        .onDisappear {
            _ = saveChanges()
        }
    }

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) {
            e.status = s
            e.markDirty()
        }
        _ = saveChanges()
    }
    private func delete(_ e: Entry) {
        SyncDeleteQueue.enqueue(.entry, id: e.id, in: context)
        withAnimation(.snappy) { context.delete(e) }
        _ = saveChanges()
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
}
