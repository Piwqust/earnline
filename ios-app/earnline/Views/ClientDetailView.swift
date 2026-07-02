import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Bindable var client: Client
    /// Entry to scroll to and flash when arriving from search.
    var highlightedEntryID: UUID? = nil

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var confirmDeleteClient = false
    @State private var saveError: String?
    @State private var draftName = ""
    @State private var nameLoaded = false
    @State private var flashedEntryID: UUID?

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
        ScrollViewReader { proxy in
            list
                .onAppear { scrollToHighlight(proxy) }
        }
    }

    private var list: some View {
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
                    .id(entry.id)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                    .listRowBackground(flashedEntryID == entry.id
                        ? Theme.blue.opacity(0.12)
                        : Color(.secondarySystemGroupedBackground))
                }
            }

            Section("Edit") {
                TextField("Name", text: $draftName)
                    .onChange(of: draftName) { _, v in
                        draftName = Validation.capped(v, max: Limits.maxClientNameLength)
                    }
                    .onSubmit(commitRename)
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

            Section {
                Button(role: .destructive) { confirmDeleteClient = true } label: {
                    Label("Delete Client", systemImage: "trash")
                }
            } footer: {
                Text("Removes the client and all of its income lines everywhere.")
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
            Text(saveError ?? String(localized: "Try again."))
        }
        .alert("Delete \(client.name)?", isPresented: $confirmDeleteClient) {
            Button("Delete", role: .destructive) { deleteClient() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes \(client.entries.count) income line(s) on every synced device.")
        }
        .onAppear {
            if !nameLoaded {
                draftName = client.name
                nameLoaded = true
            }
        }
        .onDisappear {
            commitRename()
            guard !client.isDeleted else { return }
            _ = saveChanges()
        }
    }

    /// Commit the rename on submit / leave rather than per keystroke — saving
    /// and bumping `updatedAt` on every character is churn the sync layer and
    /// disk don't need.
    private func commitRename() {
        guard !client.isDeleted else { return }
        let trimmed = Validation.trimmed(draftName, max: Limits.maxClientNameLength)
        guard !trimmed.isEmpty, trimmed != client.name else { return }
        client.name = trimmed
        client.markDirty()
        _ = saveChanges()
    }

    private func deleteClient() {
        let target = client
        dismiss()
        // Delete after the pop so nothing in this hierarchy renders a dead model.
        Task { @MainActor in
            SyncDeleteQueue.enqueue(.client, id: target.id, in: context)
            context.delete(target)
            try? context.save()
            app.queueSync(context: context)
        }
    }

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let target = highlightedEntryID, flashedEntryID == nil,
              sortedEntries.contains(where: { $0.id == target }) else { return }
        flashedEntryID = target
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo(target, anchor: .center) }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth(duration: 0.6)) { flashedEntryID = nil }
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
