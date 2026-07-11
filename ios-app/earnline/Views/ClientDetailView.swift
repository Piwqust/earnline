import SwiftUI
import SwiftData
import Charts

/// One client's page, redesigned as a content-first profile: an earned-total
/// hero, a scrubbable 12-month earnings chart in the client's color (the same
/// Health/Stocks idiom as Insights), a quiet at-a-glance stat block, the
/// status/project breakdowns, and the full history grouped by month — lazily,
/// so a client with years of lines opens instantly. Renaming, recoloring, and
/// deletion live behind the toolbar's Edit button in `EditClientSheet`,
/// keeping the page itself read-and-act.
struct ClientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    let client: Client

    @State private var editingEntry: Entry?
    @State private var pendingDelete: Entry?
    @State private var showEditSheet = false
    @State private var saveError: String?
    /// Scrub position on the earnings chart; snapped to the plotted month.
    @State private var chartSelection: Date?

    private var calendar: Calendar { .current }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 170
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
        // One bucketing pass feeds the hero, chart, stats, and month sections.
        let monthTotals = app.insights.earnedTotalsByMonth(of: client)
        let sections = historySections(monthTotals)
        return ScrollView {
            // Lazy so the month sections build as they scroll in — a client
            // with years of lines must not render them all on push.
            LazyVStack(alignment: .leading, spacing: 22) {
                heroBlock(totalAll: allTimeTotal(monthTotals))

                section("Last 12 months") { trendCard(monthTotals) }

                section("At a glance") { statsCard(monthTotals) }

                section("By status") { statusCard }

                if projectTotals.count > 1 || (projectTotals.first?.name ?? "—") != "—" {
                    section("By project") { projectsCard }
                }

                ForEach(sections, id: \.month) { monthSection in
                    historyMonth(monthSection)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
                    .accessibilityIdentifier("client.edit")
            }
        }
        .sheet(item: $editingEntry) { EditEntrySheet(entry: $0, clients: clients) }
        .sheet(isPresented: $showEditSheet) {
            EditClientSheet(
                client: client,
                otherClientNames: clients.filter { $0.id != client.id }.map(\.name),
                onDelete: deleteClient
            )
        }
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
        .undoToastHost()
    }

    // MARK: Hero — the one figure this page exists for

    private func heroBlock(totalAll: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                // The client's identity color as a compact marker — the nav
                // title already carries the name.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: client.colorHex))
                    .frame(width: 10, height: 10)
                Text("Total earned")
                    .appFont(13, .medium)
                    .foregroundStyle(Theme.label(0.5))
            }
            MoneyAmountText(baseAmount: totalAll,
                            size: 34, weight: .bold, design: .rounded,
                            relativeTo: .largeTitle,
                            color: Theme.label)
                .animation(.snappy(duration: 0.3), value: totalAll)
            metaLine
                .appFont(13)
                .foregroundStyle(Theme.label(0.45))
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    /// "12 lines · since March 2025" — or an invitation while the page is
    /// empty. A `Text` so the `^[…](inflect:)` grammar agreement actually
    /// parses (it only works through `LocalizedStringKey`, not
    /// `String(localized:)`).
    private var metaLine: Text {
        let count = client.entries.count
        guard count > 0, let first = client.entries.map(\.date).min() else {
            return Text("No income lines yet")
        }
        return Text("^[\(count) line](inflect: true) · since \(DateFormat.monthAndYear(first))")
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

    private func chartData(_ monthTotals: [Int: Decimal]) -> [(month: Date, total: Decimal)] {
        let thisMonth = DateFormat.monthStart(of: .now)
        return (0..<12).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return (month: month, total: monthTotals[Insights.monthKey(of: month)] ?? .zero)
        }
    }

    private func trendCard(_ monthTotals: [Int: Decimal]) -> some View {
        let data = chartData(monthTotals)
        let selected = chartSelection.flatMap { selection in
            data.first { calendar.isDate($0.month, equalTo: selection, toGranularity: .month) }
        }
        let hasData = data.contains { $0.total > 0 }
        let barColor = Color(hex: client.colorHex)
        return ChromeCard {
            Chart {
                ForEach(data, id: \.month) { point in
                    let isSelected = selected.map {
                        calendar.isDate($0.month, equalTo: point.month, toGranularity: .month)
                    } ?? false
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Earned", doubleValue(point.total)),
                        width: .ratio(0.62)
                    )
                    .foregroundStyle(selected != nil && !isSelected
                                     ? AnyShapeStyle(barColor.opacity(0.3))
                                     : AnyShapeStyle(barColor.gradient))
                    .cornerRadius(4)
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
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.label(0.5))
                }
            }
            .chartXSelection(value: $chartSelection)
            .frame(height: chartHeight)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .overlay {
                if !hasData {
                    Text("No earned income in the last year")
                        .appFont(11)
                        .foregroundStyle(Theme.label(0.4))
                }
            }
        }
    }

    private func chartCallout(_ point: (month: Date, total: Decimal)) -> some View {
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

    // MARK: At a glance — four quiet figures

    private func statsCard(_ monthTotals: [Int: Decimal]) -> some View {
        let thisMonth = monthTotals[Insights.monthKey(of: .now)] ?? .zero
        let activeMonths = monthTotals.values.count { $0 > 0 }
        let average = activeMonths == 0
            ? Decimal.zero
            : allTimeTotal(monthTotals) / Decimal(activeMonths)
        return ChromeCard {
            HStack(alignment: .top, spacing: 8) {
                stat("This month", value: app.primaryString(thisMonth.rounded()))
                stat("Avg / month", value: app.primaryString(average.rounded()))
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)
            HStack(alignment: .top, spacing: 8) {
                stat("Share of income", value: shareOfIncomeString(monthTotals))
                stat("Pending", value: app.primaryString(pendingTotal.rounded()))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
        }
    }

    private func stat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .appFont(13)
                .foregroundStyle(Theme.label(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .appFont(20, .semibold, design: .rounded, relativeTo: .title3)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func allTimeTotal(_ monthTotals: [Int: Decimal]) -> Decimal {
        monthTotals.values.reduce(Decimal.zero, +)
    }

    /// This client's slice of everything ever earned, e.g. "37%".
    private func shareOfIncomeString(_ monthTotals: [Int: Decimal]) -> String {
        let everyone = app.insights.ledgerSnapshot(clients)
            .earnedTotalByMonth.values.reduce(Decimal.zero, +)
        guard everyone > 0 else { return "—" }
        let fraction = NSDecimalNumber(decimal: allTimeTotal(monthTotals)).doubleValue
            / NSDecimalNumber(decimal: everyone).doubleValue
        return "\(Int((min(fraction, 9.99) * 100).rounded()))%"
    }

    /// Base-currency sum of the lines still in progress.
    private var pendingTotal: Decimal {
        client.entries
            .filter { $0.status == .inProgress }
            .reduce(Decimal.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }

    // MARK: Status & project breakdowns

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

    // MARK: History — every line, grouped by month, newest first

    private struct HistorySection {
        let month: Date
        let total: Decimal
        let entries: [Entry]
    }

    /// One grouping pass over the client's entries: newest month first,
    /// newest line first within a month, each month carrying its earned total
    /// from the shared bucketing pass.
    private func historySections(_ monthTotals: [Int: Decimal]) -> [HistorySection] {
        var buckets: [Int: [Entry]] = [:]
        for entry in client.entries where !entry.isDeleted {
            buckets[Insights.monthKey(of: entry.date, calendar: calendar), default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).compactMap { key in
            guard let month = calendar.date(from: DateComponents(year: key / 12, month: key % 12 + 1)) else {
                return nil
            }
            let entries = (buckets[key] ?? []).sorted { $0.date > $1.date }
            return HistorySection(month: month, total: monthTotals[key] ?? .zero, entries: entries)
        }
    }

    private func historyMonth(_ section: HistorySection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DateFormat.monthAndYear(section.month))
                    .appFont(15, .medium)
                    .foregroundStyle(Theme.label(0.5))
                Spacer()
                MoneyAmountText(baseAmount: section.total,
                                size: 15, weight: .medium,
                                color: Theme.label(0.5))
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 7)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ChromeCard {
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                    EntryRow(
                        entry: entry,
                        onSetStatus: { setStatus(entry, $0) },
                        onEdit: { editingEntry = entry },
                        onDelete: { pendingDelete = entry }
                    )
                    .id(entry.id)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < section.entries.count - 1 {
                        ChromeDivider(inset: 16)
                    }
                }
            }
        }
    }

    // MARK: Actions

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
