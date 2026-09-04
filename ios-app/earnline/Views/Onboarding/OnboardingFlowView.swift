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
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    /// Called once the owner taps "Let's start". The host tears the layer down
    /// and marks this workspace as introduced.
    let finish: () -> Void

    @State private var step: AppModel.OnboardingCheckpointStep = .client
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
        .task(restoreCheckpoint)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.flow")
    }

    // MARK: Steps 1 & 2

    private var wizard: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            GeometryReader { proxy in
                let illustrationWidth = min(383, max(0, proxy.size.width - 20))
                hero(illustrationWidth: illustrationWidth)
            }
        }
        // The panel responds to the keyboard, but the artwork has an explicit
        // width/height and therefore remains the same background object instead
        // of accepting the inset's reduced height proposal.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            panel
        }
    }

    /// Illustration behind, header in front — the design runs the title across
    /// the top of the artwork.
    private func hero(illustrationWidth: CGFloat) -> some View {
        ZStack(alignment: .top) {
            illustration(width: illustrationWidth)
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

    private func illustration(width: CGFloat) -> some View {
        let height = step == .client ? width * (390 / 383) : width

        return Image(step == .client ? "OnboardingClient" : "OnboardingIncome")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .fixedSize()
            .onboardingArtworkStyle()
            .id(step)
            .transition(.opacity)
            .accessibilityHidden(true)
            #if DEBUG
            .overlay {
                if AppModel.isRunningUIAutomation {
                    Color.clear
                    .accessibilityElement()
                    .accessibilityIdentifier("onboarding.illustration")
                }
            }
            #endif
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
                    // Figma: 16 pt panel content inset plus another 20 pt for
                    // the 330 pt CTA on a 402 pt canvas.
                    .padding(.horizontal, 20)
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
        if let error = mutations.save(context) {
            // `LedgerMutationStore.save` already rolled the failed transaction back.
            saveError = error
            return
        }
        createdClient = client
        app.stageOnboardingClient(client.id)
        stepFeedback += 1
        step = .income
    }

    private func recordFirstEntry(_ entry: Entry) {
        firstEntryAmount = CurrencyFormatter.string(entry.amount, code: entry.currencyCode)
        app.stageOnboardingEntry(entry.id)
        doneFeedback += 1
        step = .done
    }

    @MainActor
    private func restoreCheckpoint() async {
        guard step == .client,
              app.onboardingCheckpointStep != .client,
              let clientID = app.onboardingClientID else { return }

        var clientDescriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id == clientID }
        )
        clientDescriptor.fetchLimit = 1
        let client: Client?
        do {
            client = try context.fetch(clientDescriptor).first
        } catch {
            saveError = String(localized: "Could not restore setup. Your saved data was not changed.")
            return
        }
        guard let client else {
            app.resetOnboardingForNextLaunch()
            app.isPresentingOnboarding = true
            return
        }

        createdClient = client
        step = app.onboardingCheckpointStep

        if step == .done, let entryID = app.onboardingEntryID {
            var entryDescriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { $0.id == entryID }
            )
            entryDescriptor.fetchLimit = 1
            do {
                if let entry = try context.fetch(entryDescriptor).first {
                    firstEntryAmount = CurrencyFormatter.string(entry.amount, code: entry.currencyCode)
                } else {
                    app.stageOnboardingClient(client.id)
                    step = .income
                }
            } catch {
                saveError = String(localized: "Could not restore setup. Your saved data was not changed.")
            }
        }
    }
}
