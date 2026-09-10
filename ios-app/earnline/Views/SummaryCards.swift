import SwiftUI

/// The ledger's primary summary: one calm earnings surface with a compact
/// Insights action underneath. The total owns the hierarchy; the comparison
/// is available without taking half of the first viewport.
struct SummaryCards: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let month: Date
    let total: Decimal
    /// Earned base-currency totals ending at `month`, oldest first — drives the
    /// sparkline and the growth figure so both track the displayed month.
    let trend: [Decimal]
    let onOpenInsights: () -> Void

    /// Tracks the prior total for value-transition direction when a user edits
    /// a line or switches an explicit display context.
    @State private var previousTotal: Decimal = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            earnedCard
            statsCard
        }
        // Editing a line may update the same visible month outside the
        // scroll-boundary transaction. Keep that numeric change alive here;
        // month changes themselves are animated at the owning mutation in
        // `LedgerView` so a scrolling List never inherits an animation.
        .animation(reduceMotion ? nil : .snappy(duration: 0.34), value: total)
        .onChange(of: total) { oldValue, _ in previousTotal = oldValue }
    }

    // MARK: Earned

    private var earnedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            earnedTitle
            MoneyAmountText(baseAmount: total,
                            size: 28, weight: .semibold,
                            color: Theme.label,
                            lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1,
                            countsDownFrom: previousTotal)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.summary))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.summary)
                .strokeBorder(Theme.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Earned in \(DateFormat.month(month))")
        .accessibilityValue(app.primaryString(total))
        .accessibilityIdentifier("ledger.earned.summary")
    }

    private var earnedTitle: some View {
        Text("Earned in \(DateFormat.month(month))")
            .appFont(14, .medium)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Stats

    private var statsCard: some View {
        Button(action: onOpenInsights) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stats")
                        .appFont(15, .medium)
                        .foregroundStyle(Theme.label)
                    Text(growthText)
                        .appFont(14, .medium, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Theme.fillQuaternary, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Stats")
        .accessibilityValue(growthText)
        .accessibilityHint("Opens Insights")
        .accessibilityIdentifier("ledger.stats.summary")
    }

    /// This month against the one before it. Nil when there's no prior baseline
    /// to grow from, in which case the card just shows a dash.
    private var growthFraction: Double? {
        guard trend.count >= 2 else { return nil }
        let latest = doubleValue(trend[trend.count - 1])
        let prior = doubleValue(trend[trend.count - 2])
        guard prior > 0 else { return nil }
        return latest / prior - 1
    }

    private var growthText: String {
        // A partial calendar month is not comparable to the preceding whole
        // month. Showing its raw percentage made a healthy month look like a
        // dramatic collapse until the final day arrived.
        guard !Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) else {
            return String(localized: "So far")
        }
        guard let fraction = growthFraction else { return "—" }
        // Clamp so a wild spike (a first invoice after a dry month) can't blow
        // the card's width apart.
        let pct = Int((min(fraction, 9.99) * 100).rounded())
        return "\(pct >= 0 ? "+" : "")\(pct)%"
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
