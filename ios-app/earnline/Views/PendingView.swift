import SwiftUI
import SwiftData

/// The outstanding work list in the ChatGPT card dialect: centered title with
/// a circular glass ✕, a total row up top, then every in-progress line in one white
/// card, most urgent first. Overdue holds are flagged red, due-soon ones
/// amber. Rows reuse `EntryRow`, so the status menu lets you mark a line paid
/// straight from here (which removes it from this list).
struct PendingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    /// Scoped to in-progress rows in SQL. This list used to be derived by
    /// walking `clients.flatMap(\.entries)`, which faulted every entry in the
    /// store to find the handful that are still outstanding — the same shape
    /// `AppModel.refreshPendingReminders` already avoids with this predicate.
    @Query private var inProgressEntries: [Entry]

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var saveError: String?
    @State private var statusFeedback = 0

    init() {
        let inProgress = EntryStatus.inProgress.rawValue
        _inProgressEntries = Query(filter: #Predicate<Entry> { $0.statusRaw == inProgress })
    }

    /// Sorted here rather than in the query: "undated last" is not expressible
    /// as a `SortDescriptor`, and the scoped set is small.
    private var pending: [Entry] { Insights.sortedByUrgency(inProgressEntries) }
    private var totalPending: Decimal {
        pending.reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "Nothing pending",
                    systemImage: "checkmark.circle",
                    description: Text("In-progress lines show up here, soonest hold date first.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ChromeCard {
                            ChromeRow(icon: "clock") {
                                Text("Total").foregroundStyle(Theme.label)
                                Spacer()
                                MoneyAmountText(baseAmount: totalPending,
                                                size: 17, weight: .semibold, design: .rounded,
                                                color: Theme.label)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            CardHeader("Lines")
                            ChromeCard {
                                ForEach(Array(pending.enumerated()), id: \.element.id) { index, entry in
                                    row(entry)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    if index < pending.count - 1 {
                                        ChromeDivider(inset: 16)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .sheetHeader("Pending", onClose: { dismiss() })
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .undoToastHost()
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
        .alert("Delete income line?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) { delete(entry); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text("\(CurrencyFormatter.string(entry.amount, code: entry.currencyCode)) · \(entry.task)")
        }
        .saveErrorAlert($saveError)
        .sensoryFeedback(.impact(weight: .light), trigger: statusFeedback)
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let client = entry.client {
                    Text(client.name)
                        .appFont(12, .semibold)
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
        if app.insights.isOverdue(entry) {
            badge("Overdue", systemImage: "exclamationmark.circle.fill", tint: Theme.statusCanceled)
        } else if let hold = entry.holdUntil, let days = daysUntil(hold) {
            if days <= 3 {
                badge("Due \(DateFormat.dotted(hold))", systemImage: "clock.fill", tint: Theme.statusProgress)
            } else {
                badge("Hold \(DateFormat.dotted(hold))", systemImage: "calendar", tint: Theme.tertiaryLabel)
            }
        }
    }

    private func badge(_ title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .appFont(12, .semibold)
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
        if save() { statusFeedback += 1 }
    }

    private func delete(_ entry: Entry) {
        saveError = app.delete(entry, context: context)
    }

    @discardableResult
    private func save() -> Bool {
        saveError = app.save(context)
        return saveError == nil
    }
}
