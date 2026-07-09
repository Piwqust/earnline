import SwiftUI
import SwiftData

/// One client's page in the ChatGPT card dialect: gray page, white grouped
/// cards with inset hairlines — status breakdown, projects, lines, editing,
/// and the destructive action isolated in its own red row at the end.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Bindable var client: Client

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var confirmDeleteClient = false
    @State private var saveError: String?
    @State private var draftName = ""
    @State private var nameLoaded = false

    /// One namespace so the color-selection ring slides between swatches
    /// (matched geometry) — the same treatment as `NewClientSheet`.
    @Namespace private var swatchSelection

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
            VStack(alignment: .leading, spacing: 22) {
                headerBlock

                section("By status") { statusCard }

                if projectTotals.count > 1 || (projectTotals.first?.name ?? "—") != "—" {
                    section("By project") { projectsCard }
                }

                if !sortedEntries.isEmpty {
                    section("Lines") { linesCard }
                }

                section("Edit") { editCard }

                VStack(alignment: .leading, spacing: 0) {
                    deleteCard
                    CardFootnote {
                        Text("Removes the client and all of its income lines everywhere.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
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
        .saveErrorAlert($saveError)
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
        .undoToastHost()
    }

    // MARK: Sections

    private func section(_ title: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title)
            content()
        }
    }

    private var headerBlock: some View {
        HStack(spacing: 10) {
            Text(client.name)
                .appFont(16, .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.tint(Color(hex: client.colorHex)), in: .capsule)
            Spacer()
            MoneyAmountText(baseAmount: totalAll,
                            size: 20, weight: .semibold,
                            color: Theme.label)
                .animation(.snappy(duration: 0.3), value: totalAll)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var statusCard: some View {
        ChromeCard {
            ForEach(EntryStatus.allCases) { s in
                let t = statusTotal(s)
                ChromeRow(icon: nil) {
                    Image(systemName: s.symbol)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(s.tint)
                        .frame(width: 24)
                    Text(s.title).foregroundStyle(Theme.label)
                    Spacer()
                    Text("\(t.count)")
                        .foregroundStyle(Theme.label(0.4)).monospacedDigit()
                        .contentTransition(.numericText())
                    MoneyAmountText(baseAmount: t.sum,
                                    size: 17,
                                    color: Theme.label(0.7))
                }
                .animation(.snappy(duration: 0.3), value: t.sum)
                if s != EntryStatus.allCases.last {
                    ChromeDivider()
                }
            }
        }
    }

    private var projectsCard: some View {
        ChromeCard {
            ForEach(Array(projectTotals.enumerated()), id: \.element.name) { index, p in
                ChromeRow(icon: nil) {
                    Text(p.name).foregroundStyle(Theme.label).lineLimit(1)
                    Spacer()
                    MoneyAmountText(baseAmount: p.sum,
                                    size: 17,
                                    color: Theme.label(0.7))
                        .animation(.snappy(duration: 0.3), value: p.sum)
                }
                if index < projectTotals.count - 1 {
                    ChromeDivider(inset: 16)
                }
            }
        }
    }

    private var linesCard: some View {
        ChromeCard {
            ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                EntryRow(
                    entry: entry,
                    onSetStatus: { setStatus(entry, $0) },
                    onEdit: { editingEntry = entry },
                    onDelete: { pendingDelete = entry }
                )
                .id(entry.id)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if index < sortedEntries.count - 1 {
                    ChromeDivider(inset: 16)
                }
            }
        }
    }

    private var editCard: some View {
        ChromeCard {
            ChromeRow(icon: "pencil") {
                TextField("Name", text: $draftName)
                    .onChange(of: draftName) { _, v in
                        draftName = Validation.capped(v, max: Limits.maxClientNameLength)
                    }
                    .onSubmit(commitRename)
            }
            ChromeDivider()
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Theme.clientPalette, id: \.self) { hex in
                    swatch(hex)
                }
            }
            .padding(16)
        }
    }

    /// Selection ring in the ink color — the same ChatGPT accent-picker
    /// treatment as `NewClientSheet`: the ring slides between swatches via
    /// matched geometry and the tapped swatch gives a small pop.
    private func swatch(_ hex: String) -> some View {
        let selected = hex == client.colorHex
        return Circle()
            .fill(Color(hex: hex))
            .frame(height: 30)
            .overlay {
                Circle().strokeBorder(Theme.label(0.08), lineWidth: 0.5)
            }
            .overlay {
                if selected {
                    Circle()
                        .stroke(Theme.label(0.85), lineWidth: 2.5)
                        .padding(-4)
                        .matchedGeometryEffect(id: "swatchRing", in: swatchSelection)
                }
            }
            .scaleEffect(selected ? 1.08 : 1)
            .contentShape(.circle)
            .onTapGesture {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                    client.colorHex = hex
                }
                client.markDirty()
                _ = saveChanges()
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Destructive action isolated in its own card — ChatGPT's "Log out" row.
    private var deleteCard: some View {
        ChromeCard {
            Button { confirmDeleteClient = true } label: {
                ChromeRow(icon: nil) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.statusCanceled)
                        .frame(width: 24)
                    Text("Delete Client").foregroundStyle(Theme.statusCanceled)
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
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

    private func setStatus(_ e: Entry, _ s: EntryStatus) {
        withAnimation(.snappy) {
            e.status = s
            e.markDirty()
        }
        _ = saveChanges()
    }
    private func delete(_ e: Entry) {
        saveError = app.delete(e, context: context)
    }

    @discardableResult
    private func saveChanges() -> Bool {
        saveError = app.save(context)
        return saveError == nil
    }
}
