import SwiftUI

/// The floating summary cards own the scroll-driven displayed-month dependency,
/// so month changes do not invalidate every ledger row.
struct LedgerSummaryHeader: View {
    @Environment(AppModel.self) private var app

    let monthlyTotals: [Int: Decimal]
    var isSearching = false
    var searchHitCount = 0
    var searchEarnedTotal: Decimal = 0
    var hasSearchFilter = false
    let onOpenStats: () -> Void

    private var displayedTotal: Decimal {
        monthlyTotals[Insights.monthKey(of: app.displayedMonth)] ?? .zero
    }

    private var displayedTrend: [Decimal] {
        let calendar = Calendar.current
        return (0..<6).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: app.displayedMonth)
                .map { monthlyTotals[Insights.monthKey(of: $0)] ?? .zero }
        }
    }

    var body: some View {
        Group {
            if isSearching {
                compactSearchHeader
            } else {
                SummaryCards(
                    month: app.displayedMonth,
                    total: displayedTotal,
                    trend: displayedTrend,
                    onOpenStats: onOpenStats
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: app.displayedMonth)
        .animation(.snappy, value: isSearching)
    }

    private var compactSearchHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormat.month(app.displayedMonth))
                    .appFont(13, .medium)
                    .foregroundStyle(.secondary)
                Text(app.primaryString(displayedTotal))
                    .appFont(17, .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.label)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            if hasSearchFilter {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("^[\(searchHitCount) result](inflect: true)")
                        .appFont(13, .medium)
                        .foregroundStyle(.secondary)
                    Text(app.primaryString(searchEarnedTotal))
                        .appFont(17, .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.summary))
        .accessibilityElement(children: .combine)
    }
}
