import SwiftUI

/// The empty ledger's setup checklist — the standard two-step form: a progress
/// line, then one card per step, each carrying its own action.
///
/// Both steps are live controls rather than an illustration of the workflow, so
/// the card the owner is reading is also the button they press. Only those
/// controls take Liquid Glass; the heading and the progress line stay in the
/// content layer, where glass does not belong.
///
/// Hand-rolled rather than `ContentUnavailableView`: inside the ledger's List
/// row the system component stretches its action button to fill the whole
/// remaining viewport (iOS 26), which reads as a broken giant pill.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let client: Client?
    var onAddClient: () -> Void
    var onAddIncome: () -> Void

    private enum StepState {
        case current
        case complete
        case upcoming
    }

    /// The ledger's actual required order: income belongs to a client, so step
    /// two cannot be taken until step one is done.
    private var hasClient: Bool { client != nil }
    private var completedCount: Int { hasClient ? 1 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Set up your ledger")
                .appFont(24, .bold, relativeTo: .title2)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)

            Text("Two steps and your first line is in.")
                .appFont(15, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            progress
                .padding(.top, 16)

            steps
                .padding(.top, 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.empty.onboarding")
    }

    // MARK: Progress

    /// One segment per step rather than a measured bar: it needs no geometry,
    /// and it reads as "two things to do" at a glance, which a continuous bar
    /// at 50% does not.
    private var progress: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index < completedCount ? app.accentColor : Theme.fillQuaternary)
                        .frame(height: 4)
                }
            }
            .animation(.smooth(duration: 0.3), value: completedCount)

            Text("\(completedCount) of 2")
                .appFont(13, .medium, relativeTo: .caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(completedCount) of 2 done"))
    }

    // MARK: Steps

    /// One container for the pair so the two cards share a rendering pass and
    /// blend consistently, as grouped glass is meant to.
    private var steps: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 10) {
                step(
                    number: 1,
                    title: "Add your first client",
                    detail: hasClient
                        ? Text(verbatim: client?.name ?? "")
                        : Text("Who the money comes from"),
                    state: hasClient ? .complete : .current,
                    identifier: "ledger.empty.client",
                    action: onAddClient
                )

                step(
                    number: 2,
                    title: "Write your first income",
                    detail: Text("The amount, and what the work was"),
                    state: hasClient ? .current : .upcoming,
                    identifier: "ledger.empty.income",
                    action: onAddIncome
                )
            }
        }
    }

    private func step(
        number: Int,
        title: LocalizedStringKey,
        detail: Text,
        state: StepState,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                badge(number: number, state: state)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(16, .semibold, relativeTo: .body)
                        .foregroundStyle(Theme.label)
                        .strikethrough(state == .complete, color: Theme.secondaryLabel)

                    // Explicit rather than `.secondary`: a glass button tints
                    // its label with the button's tint, so the semantic
                    // hierarchy colours come back out in the accent.
                    detail
                        .appFont(13, relativeTo: .subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                // A finished step is a record, not an action — and at
                // accessibility sizes the chevron costs width the copy needs.
                if state != .complete, !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .appFont(13, .semibold)
                        .foregroundStyle(Theme.tertiaryLabel)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        // Step two is not merely unfinished, it is unreachable: income has to
        // belong to a client. Completed steps have nothing left to do.
        .disabled(state != .current)
        .opacity(state == .current ? 1 : 0.55)
        .animation(.smooth(duration: 0.3), value: state == .current)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(state == .complete ? Text("Done") : Text(""))
    }

    private func badge(number: Int, state: StepState) -> some View {
        ZStack {
            switch state {
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, app.accentColor)
            case .current, .upcoming:
                Circle()
                    .fill(state == .current ? app.accentColor : Theme.fillQuaternary)
                    .overlay {
                        Text(verbatim: "\(number)")
                            .appFont(14, .bold)
                            .foregroundStyle(state == .current ? .white : Theme.secondaryLabel)
                    }
            }
        }
        .frame(width: 26, height: 26)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)
    }
}
