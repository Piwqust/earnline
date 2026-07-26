import SwiftUI

/// Hand-rolled rather than `ContentUnavailableView`: inside the ledger's
/// List row the system component stretches its action button to fill the
/// whole remaining viewport (iOS 26), which reads as a broken giant pill.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let client: Client?
    var onStart: () -> Void

    private enum WorkflowStepState: Equatable {
        case current
        case complete
        case upcoming
    }

    private enum WorkflowStep {
        case client
        case income
    }

    private var isAddingClient: Bool { client == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            phaseSymbol
                .padding(.bottom, 14)

            phaseTitle
                .appFont(26, .bold, relativeTo: .title)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            phaseDescription
                .appFont(16, relativeTo: .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            workflowPath
                .padding(.top, 24)

            Button(action: onStart) {
                actionLabel
                    .appFont(17, .semibold, relativeTo: .headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .padding(.top, 20)
            .accessibilityIdentifier("ledger.empty.primary")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.empty.onboarding")
        .padding(.vertical, 12)
    }

    private var phaseSymbol: some View {
        Image(systemName: isAddingClient ? "person.crop.circle.badge.plus" : "checkmark.circle.fill")
            .font(.system(size: 29, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(app.accentColor)
            .frame(width: 54, height: 54)
            .background(app.accentColor.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var phaseTitle: some View {
        if isAddingClient {
            Text("Start with a client")
        } else {
            Text("Ready to record income")
        }
    }

    @ViewBuilder
    private var phaseDescription: some View {
        if isAddingClient {
            Text("Start here — add who pays you, then write your first income line.")
        } else {
            Text("Add the amount and a short description.")
        }
    }

    @ViewBuilder
    private var actionLabel: some View {
        if isAddingClient {
            Label("Add client", systemImage: "person.crop.circle.badge.plus")
        } else {
            Label("Add income", systemImage: "plus")
        }
    }

    @ViewBuilder
    private var workflowPath: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalWorkflowPath
        } else {
            horizontalWorkflowPath
        }
    }

    private var horizontalWorkflowPath: some View {
        HStack(alignment: .top, spacing: 10) {
            workflowStep(
                .client,
                title: "Client",
                detail: isAddingClient
                    ? String(localized: "Who the income belongs to")
                    : client?.name ?? String(localized: "Client"),
                state: isAddingClient ? .current : .complete
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .padding(.top, 10)
                .accessibilityHidden(true)

            workflowStep(
                .income,
                title: "Income",
                detail: String(localized: "Amount and work details"),
                state: isAddingClient ? .upcoming : .current
            )
        }
        .padding(14)
        .background(Theme.fillQuaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var verticalWorkflowPath: some View {
        VStack(alignment: .leading, spacing: 14) {
            workflowStep(
                .client,
                title: "Client",
                detail: isAddingClient
                    ? String(localized: "Who the income belongs to")
                    : client?.name ?? String(localized: "Client"),
                state: isAddingClient ? .current : .complete
            )

            HStack(spacing: 8) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: 20)
                    .padding(.leading, 9)
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
                    .accessibilityHidden(true)
            }

            workflowStep(
                .income,
                title: "Income",
                detail: String(localized: "Amount and work details"),
                state: isAddingClient ? .upcoming : .current
            )
        }
        .padding(14)
        .background(Theme.fillQuaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func workflowStep(
        _ step: WorkflowStep,
        title: LocalizedStringKey,
        detail: String,
        state: WorkflowStepState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: symbol(for: step, state: state))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint(for: state))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                Text(title)
                    .appFont(15, .semibold, relativeTo: .body)
                    .foregroundStyle(Theme.label)
            }

            Text(detail)
                .appFont(13, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func symbol(for step: WorkflowStep, state: WorkflowStepState) -> String {
        switch (step, state) {
        case (.client, .complete):
            "checkmark.circle.fill"
        case (.client, _):
            "person.crop.circle"
        case (.income, _):
            "banknote"
        }
    }

    private func tint(for state: WorkflowStepState) -> Color {
        switch state {
        case .current, .complete:
            app.accentColor
        case .upcoming:
            Theme.secondaryLabel
        }
    }
}
