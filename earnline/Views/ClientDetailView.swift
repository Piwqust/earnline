import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Bindable var client: Client

    @State private var editingEntry: Entry?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private var sortedEntries: [Entry] { client.entries.sorted { $0.date > $1.date } }

    private var totalAll: Decimal {
        client.entries.reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }
    private func statusTotal(_ s: EntryStatus) -> (count: Int, sum: Decimal) {
        let items = client.entries.filter { $0.status == s }
        return (items.count, items.reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) })
    }
    private var projectTotals: [(name: String, sum: Decimal)] {
        var dict: [String: Decimal] = [:]
        for e in client.entries {
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
                        Text(app.primaryString(totalAll))
                            .font(.system(size: 20, weight: .semibold))
                        Text(app.secondaryString(totalAll))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.label(0.5))
                    }
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
                        Text("\(t.count)").foregroundStyle(Theme.label(0.4)).monospacedDigit()
                        Text(app.primaryString(t.sum)).foregroundStyle(Theme.label(0.7)).monospacedDigit()
                    }
                }
            }

            if projectTotals.count > 1 || (projectTotals.first?.name ?? "—") != "—" {
                Section("By project") {
                    ForEach(projectTotals, id: \.name) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            Text(app.primaryString(p.sum)).foregroundStyle(Theme.label(0.7)).monospacedDigit()
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
                        onDelete: { delete(entry) }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
            }

            Section("Edit") {
                TextField("Name", text: $client.name)
                    .onChange(of: client.name) { _, v in
                        client.name = Validation.capped(v, max: Limits.maxClientNameLength)
                        client.markDirty()
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
                                try? context.save()
                                app.queueSync(context: context)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
        .onDisappear {
            try? context.save()
            app.queueSync(context: context)
        }
    }

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) {
            e.status = s
            e.markDirty()
        }
        try? context.save()
        app.queueSync(context: context)
    }
    private func delete(_ e: Entry) {
        SyncDeleteQueue.enqueue(.entry, id: e.id, in: context)
        withAnimation(.snappy) { context.delete(e) }
        try? context.save()
        app.queueSync(context: context)
    }
}
