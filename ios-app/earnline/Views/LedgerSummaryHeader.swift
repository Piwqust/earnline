import SwiftUI

/// The floating summary cards own the scroll-driven displayed-month dependency,
/// so month changes do not invalidate every ledger row.
struct LedgerSummaryHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let monthlyTotals: [Int: Decimal]
    var isSearching = false
    var searchHitCount = 0
    var searchEarnedTotal: Decimal = 0
    var hasSearchFilter = false
    var hasAnyEntries = true

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
            } else if !hasAnyEntries {
                firstEarningsHeader
            } else {
                SummaryCards(
                    month: app.displayedMonth,
                    total: displayedTotal,
                    trend: displayedTrend
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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

    @ViewBuilder
    private var firstEarningsHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    firstEarningsTitle
                    firstEarningsAmount
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    firstEarningsTitle
                    Spacer(minLength: 12)
                    firstEarningsAmount
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ledger.firstEarnings.summary")
    }

    private var firstEarningsTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Earnings")
                .appFont(22, .bold, relativeTo: .title2)
                .foregroundStyle(Theme.label)
            Text(DateFormat.monthAndYear(app.displayedMonth))
                .appFont(14, .medium, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var firstEarningsAmount: some View {
        Text(app.primaryString(displayedTotal))
            .appFont(32, .bold, design: .rounded, relativeTo: .title)
            .monospacedDigit()
            .foregroundStyle(Theme.label)
            .contentTransition(.numericText())
    }
}
