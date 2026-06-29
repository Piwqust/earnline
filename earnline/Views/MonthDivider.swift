import SwiftUI

/// A month separator in the continuous ledger, carrying that month's subtotal.
struct MonthDivider: View {
    let title: String
    var total: String? = nil

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
                Text(total)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.label(0.4))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
