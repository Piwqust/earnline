import SwiftUI

/// The floating glass header: "Earned in <month>" with the running total.
struct SummaryPill: View {
    @Environment(AppModel.self) private var app
    let month: Date
    let total: Decimal

    /// Tracks the prior total so the digits roll in the natural direction.
    @State private var previousTotal: Decimal = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Earned in \(DateFormat.month(month))")
                .font(.labelMed)
                .foregroundStyle(Theme.label(0.6))
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(app.primaryString(total))
                    .font(.summaryTotal)
                    .foregroundStyle(Theme.label)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: total < previousTotal))
                Text(app.secondaryString(total))
                    .font(.caption)
                    .foregroundStyle(Theme.label(0.6))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: total < previousTotal))
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.summary))
        .contentShape(.rect(cornerRadius: Theme.Radius.summary))
        .animation(.snappy(duration: 0.34), value: total)
        .onChange(of: total) { oldValue, _ in previousTotal = oldValue }
    }
}
