import SwiftUI
import SwiftData

/// Step 2 — "Create your first **earnline**".
///
/// This is not a mock of the ledger; it *is* the ledger's own row stack for the
/// client just created — the same `MonthDivider`, `ClientChip`, and
/// `SmartComposer` that `LedgerRowsView` builds. Submitting here writes a real
/// entry, which is what advances the flow.
struct OnboardingIncomeStep: View {
    let client: Client
    let month: Date
    let onCommit: (Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonthDivider(title: DateFormat.month(month))

            // The chip is the ledger's, drawn exactly as the design shows it —
            // but inert. Its two controls (open the client, toggle the
            // composer) would both fight a flow whose composer is already open
            // and whose only exit is committing a line.
            ClientChip(
                client: client,
                total: 0,
                onOpen: {},
                onAdd: {}
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            SmartComposer(
                client: client,
                month: month,
                usesDashedOutline: false,
                onCommit: onCommit
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.income")
    }
}
