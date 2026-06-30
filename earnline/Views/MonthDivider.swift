import SwiftUI

/// A month separator in the continuous ledger, carrying that month's subtotal.
struct MonthDivider: View {
    let title: String
    var total: Decimal? = nil

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 28, height: 1)
            Text(title)
                .font(.labelMed)
                .foregroundStyle(Theme.label(0.6))
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            if let total {
                MoneyAmountText(baseAmount: total,
                                font: .system(size: 13, weight: .medium),
                                color: Theme.label(0.4),
                                minimumScaleFactor: 0.7)
                    .animation(.snappy(duration: 0.3), value: total)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
