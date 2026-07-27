import SwiftUI
import SwiftData

/// The first-run flow: name a client, log the first earning, done.
///
/// It is a wizard that *makes the real thing* rather than an explainer — both
/// steps write to the live store through the app's own controls, and the last
/// screen is the actual ledger with the result in it. That is why the flow is
/// hosted as a layer over `LedgerView` (see `earnlineApp.primaryContent`)
/// rather than presented as a sheet: step 3 needs the ledger behind it.
///
/// There is deliberately no Skip. The ledger is useless without a client, and
/// the design treats both steps as the shortest possible path to a populated
/// notebook.
///
/// Figma: node `471:4904` (`Onboarding_1` … `Onboarding_3`).
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    /// Called once the owner taps "Let's start". The host tears the layer down
    /// and marks this workspace as introduced.
    let finish: () -> Void

    private enum Step: Int {
        case client, income, done
    }

    @State private var step: Step = .client
    @State private var name = ""
    /// Blue, as the design draws it — and the same tone the live chip takes.
    @State private var colorHex = Theme.blue.hexString
    @State private var createdClient: Client?
    @State private var firstEntryAmount: String?
    @State private var saveError: String?
    @State private var stepFeedback = 0
    @State private var doneFeedback = 0

    /// The month the flow writes into — the one the ledger opens on.
    private var month: Date { DateFormat.monthStart(of: .now) }

    private var existingNames: [String] {
        clients.filter { !$0.isInvalidated }.map(\.name)
    }

    private var clientValidation: ClientNameValidation {
        Validation.validateClientName(name, existingNames: existingNames)
    }

    var body: some View {
        Group {
            switch step {
            case .client, .income:
                wizard
            case .done:
                OnboardingDoneOverlay(
                    clientName: createdClient?.name ?? "",
                    firstAmount: firstEntryAmount ?? "",
                    start: finish
                )
            }
        }
        .animation(.smooth(duration: 0.4), value: step)
        .sensoryFeedback(.selection, trigger: stepFeedback)
        .sensoryFeedback(.success, trigger: doneFeedback)
        .saveErrorAlert($saveError, title: "Could not create client")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.flow")
    }

    // MARK: Steps 1 & 2

    private var wizard: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            hero
        }
        // The panel rides the bottom safe area, so it lifts above the keyboard
        // on the income step exactly as the design draws it.
        .safeAreaInset(edge: .bottom, spacing: 0) { panel }
    }

    /// Illustration behind, header in front — the design runs the title across
    /// the top of the artwork.
    private var hero: some View {
        ZStack(alignment: .top) {
            illustration
                .padding(.top, 34)

            OnboardingStepHeader(
                step: step.rawValue,
                titlePrefix: step == .client ? "Create your " : "Create your first ",
                titleSubject: step == .client ? "first client" : "earnline"
            )
        }
        .padding(.top, 17)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var illustration: some View {
        Image(step == .client ? "OnboardingClient" : "OnboardingIncome")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 383)
            .id(step)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var panel: some View {
        OnboardingPanel {
            switch step {
            case .client:
                OnboardingClientStep(
                    name: $name,
                    colorHex: $colorHex,
                    // Stay quiet until there is something typed to be wrong about.
                    validationMessage: name.isEmpty ? nil : clientValidation.message,
                    submit: createClient
                )
                PillCTA("Create client",
                        isEnabled: clientValidation.validName != nil,
                        action: createClient)
                    .accessibilityIdentifier("onboarding.primary")
            case .income:
                if let createdClient, !createdClient.isInvalidated {
                    OnboardingIncomeStep(
                        client: createdClient,
                        month: month,
                        onCommit: recordFirstEntry
                    )
                }
            case .done:
                EmptyView()
            }
        }
    }

    // MARK: Actions

    private func createClient() {
        guard let validName = clientValidation.validName else { return }
        let client = Client(name: validName, colorHex: colorHex, sortIndex: clients.count)
        context.insert(client)
        if let error = app.save(context) {
            // `AppModel.save` already rolled the failed transaction back.
            saveError = error
            return
        }
        createdClient = client
        stepFeedback += 1
        step = .income
    }

    private func recordFirstEntry(_ entry: Entry) {
        firstEntryAmount = CurrencyFormatter.string(entry.amount, code: entry.currencyCode)
        doneFeedback += 1
        step = .done
    }
}
