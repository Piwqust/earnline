import SwiftUI
import SwiftData

/// The outstanding work list: every in-progress line, most urgent first. Overdue
/// holds are flagged red, due-soon ones amber. Rows reuse `EntryRow`, so the
/// status menu lets you mark a line paid (which removes it from this list).
struct PendingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var saveError: String?

    private var pending: [Entry] { app.pendingEntries(clients) }
    private var totalPending: Decimal {
        pending.reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pending.isEmpty {
                    ContentUnavailableView(
                        "Nothing pending",
                        systemImage: "checkmark.circle",
                        description: Text("In-progress lines show up here, soonest hold date first.")
                    )
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Total pending").foregroundStyle(Theme.label(0.6))
                                Spacer()
                                MoneyAmountText(baseAmount: totalPending,
                                                font: .system(size: 18, weight: .semibold),
                                                color: Theme.label)
                            }
                        }
                        Section {
                            ForEach(pending) { entry in
                                row(entry)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
            .alert("Delete income line?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { entry in
                Button("Delete", role: .destructive) { delete(entry); pendingDelete = nil }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { entry in
                Text("\(CurrencyFormatter.string(entry.amount, code: entry.currencyCode)) · \(entry.task)")
            }
            .alert("Could not save changes", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Try again.")
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let client = entry.client {
                    Text(client.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: client.colorHex), in: .capsule)
                }
                Spacer(minLength: 6)
                holdBadge(entry)
            }
            EntryRow(
                entry: entry,
                onSetStatus: { setStatus(entry, $0) },
                onEdit: { editingEntry = entry },
                onDelete: { pendingDelete = entry }
            )
        }
    }

    @ViewBuilder
    private func holdBadge(_ entry: Entry) -> some View {
        if app.isOverdue(entry) {
            badge("Overdue", systemImage: "exclamationmark.circle.fill", tint: Theme.statusCanceled)
        } else if let hold = entry.holdUntil, let days = daysUntil(hold) {
            if days <= 3 {
                badge("Due \(DateFormat.dotted(hold))", systemImage: "clock.fill", tint: Theme.statusProgress)
            } else {
                badge("Hold \(DateFormat.dotted(hold))", systemImage: "calendar", tint: Theme.label(0.45))
            }
        }
    }

    private func badge(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
    }

    private func daysUntil(_ date: Date) -> Int? {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day
    }

    private func setStatus(_ entry: Entry, _ status: EntryStatus) {
        withAnimation(.snappy) { entry.status = status; entry.markDirty() }
        if save() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    private func delete(_ entry: Entry) {
        SyncDeleteQueue.enqueue(.entry, id: entry.id, in: context)
        withAnimation(.snappy) { context.delete(entry) }
        _ = save()
    }

    @discardableResult
    private func save() -> Bool {
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
