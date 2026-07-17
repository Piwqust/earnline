import SwiftUI
import SwiftData

/// Income at a glance. Ledger models are captured once into a Sendable input and
/// aggregated off the main actor, keeping sheet presentation and interaction
/// independent from the size of the ledger.
struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Entry.updatedAt, order: .reverse) private var entries: [Entry]

    /// The Monthly income card's charted window; the other cards keep fixed,
    /// captioned periods instead of following a global toggle.
    @State private var chartWindow = 6
    @State private var selectedDay: Date?
    @State private var dashboard: InsightsDashboardSnapshot?

    private var calendar: Calendar { .current }

    /// O(1) in the entry count because the query is already newest-first. It
    /// catches edits, insertions, deletions, client changes, and
    /// currency-setting changes without hashing every field during every render.
    private var dashboardRevision: DashboardRevision {
        DashboardRevision(
            entryCount: entries.count,
            latestEntryUpdate: entries.first?.updatedAt,
            clientCount: clients.count,
            latestClientUpdate: clients.compactMap(\.updatedAt).max(),
            baseCurrencyCode: app.baseCurrencyCode,
            secondaryCurrencyCode: app.secondaryCurrencyCode,
            rate: app.rate
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let dashboard {
                    dashboardContent(dashboard)
                } else {
                    dashboardSkeleton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Shared sheet header — leading glass ✕, centered title, soft scroll-edge
        // frost. See `sheetHeader`.
        .sheetHeader("Insights", onClose: { dismiss() })
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .accessibilityIdentifier("insights.sheet")
        .task(id: dashboardRevision) { await loadDashboard() }
    }

    private struct DashboardRevision: Hashable {
        let entryCount: Int
        let latestEntryUpdate: Date?
        let clientCount: Int
        let latestClientUpdate: Date?
        let baseCurrencyCode: String
        let secondaryCurrencyCode: String
        let rate: Double
    }

    @MainActor
    private func loadDashboard() async {
        let input = InsightsDashboardInput(clients: clients, converter: app.converter)
        await Task.yield()
        let snapshot = await Task.detached(priority: .userInitiated) {
            input.dashboardSnapshot()
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.22)) {
            dashboard = snapshot
        }
    }

    @ViewBuilder
    private func dashboardContent(_ snapshot: InsightsDashboardSnapshot) -> some View {
        let map = snapshot.dailyEarnings
        let maxDaily = map.values.max() ?? .zero
        let heatTotal = map.values.reduce(Decimal.zero, +)

        if snapshot.unsupportedCurrencyCount > 0 {
            Label("\(snapshot.unsupportedCurrencyCount) line(s) are excluded from these totals because no conversion rate is set.",
                  systemImage: "exclamationmark.triangle.fill")
                .appFont(13)
                .foregroundStyle(Theme.statusProgress)
                .accessibilityLabel("\(snapshot.unsupportedCurrencyCount) lines are excluded from consolidated totals because no conversion rate is set")
        }

        // No section headings or period captions — each card explains itself
        // (the chart carries its own total and period line), and the finer
        // print lives in Help, not between the cards.
        EarningsChartCard(
            points: snapshot.monthlyIncome.map {
                .init(month: $0.month, total: $0.total, previousTotal: $0.previousTotal)
            },
            tint: app.accentColor,
            window: $chartWindow
        )
        .accessibilityIdentifier("insights.monthlyIncomeChart")

        EarningsHeatmapCard(clients: clients,
                            map: map,
                            maxDaily: maxDaily,
                            heatTotal: heatTotal,
                            months: snapshot.months,
                            selectedDay: $selectedDay)

        statsCard(snapshot)

        if !snapshot.clientTotals.isEmpty {
            topClientsCard(snapshot.clientTotals)
        }
    }

    private var dashboardSkeleton: some View {
        ChromeCard {
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing insights")
                    .appFont(13, .medium)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
        .accessibilityIdentifier("insights.loading")
    }

    // MARK: Stats — three headline figures in one card

    private func statsCard(_ snapshot: InsightsDashboardSnapshot) -> some View {
        ChromeCard {
            HStack(alignment: .top, spacing: 8) {
                heroStat("This year", value: app.primaryString(snapshot.yearToDateTotal.rounded()))
                heroStat("Best month", value: snapshot.bestMonth.map { app.primaryString($0.total.rounded()) } ?? "—")
                heroStat("Avg / month", value: app.primaryString(snapshot.averageMonth.rounded()))
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
        }
    }

    private func heroStat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .appFont(13)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .appFont(23, .bold, design: .rounded, relativeTo: .title2)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Top clients — orb first, ranked breakdown below

    private func topClientsCard(_ breakdown: [InsightsDashboardSnapshot.ClientTotal]) -> some View {
        let total = breakdown.reduce(Decimal.zero) { $0 + $1.total }
        let shown = Array(breakdown.prefix(4))
        let othersTotal = breakdown.dropFirst(4).reduce(Decimal.zero) { $0 + $1.total }
        let segments = shown.map { (color: Color(hex: $0.colorHex), value: $0.total, isMuted: false) }
            + (othersTotal > 0 ? [(color: Theme.label(0.3), value: othersTotal, isMuted: true)] : [])

        return ChromeCard {
            VStack(spacing: 22) {
                ClientOrbChart(segments: segments, diameter: 154)
                    .accessibilityIdentifier("insights.clientOrb")

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Client share")
                        Spacer()
                        Text("Income")
                    }
                    .appFont(12, .semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 40)
                    .padding(.bottom, 6)

                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                        clientBreakdownRow(rank: index + 1,
                                           name: row.name,
                                           total: row.total,
                                           color: Color(hex: row.colorHex),
                                           whole: total)
                        if index < shown.count - 1 || othersTotal > 0 { ChromeDivider(inset: 0) }
                    }
                    if othersTotal > 0 {
                        clientBreakdownRow(rank: nil,
                                           name: String(localized: "Other clients"),
                                           total: othersTotal,
                                           color: Theme.label(0.3),
                                           whole: total)
                    }
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("insights.topClients")
    }

    /// A ranked, finance-native row. Exact values stay typographically aligned
    /// while the short track makes relative share visible without asking the
    /// decorative orb to carry all of the interpretation work.
    private func clientBreakdownRow(
        rank: Int?,
        name: String,
        total: Decimal,
        color: Color,
        whole: Decimal
    ) -> some View {
        let share = ratio(total, whole)
        return HStack(alignment: .top, spacing: 12) {
            Text(rank.map(String.init) ?? "•••")
                .appFont(12, .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        clientName(name)
                        Spacer(minLength: 8)
                        clientAmount(total)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        clientName(name)
                        clientAmount(total)
                    }
                }

                HStack(spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fillQuaternary)
                            Capsule()
                                .fill(color)
                                .frame(width: max(4, proxy.size.width * CGFloat(share)))
                        }
                    }
                    .frame(height: 5)

                    Text(percentString(share))
                        .appFont(12, .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 56 : 40,
                               alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private func clientName(_ name: String) -> some View {
        Text(name)
            .appFont(15, .semibold)
            .foregroundStyle(Theme.label)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clientAmount(_ total: Decimal) -> some View {
        Text(app.primaryString(total))
            .appFont(15, .semibold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
    }

    // MARK: Helpers

    private func ratio(_ value: Decimal, _ whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return NSDecimalNumber(decimal: value).doubleValue / NSDecimalNumber(decimal: whole).doubleValue
    }

    /// "37%" — clamped so a wild outlier can't blow the layout apart.
    private func percentString(_ fraction: Double) -> String {
        "\(Int((min(fraction, 9.99) * 100).rounded()))%"
    }
}
