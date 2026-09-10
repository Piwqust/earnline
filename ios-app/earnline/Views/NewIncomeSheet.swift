import SwiftUI
import SwiftData

/// Direct income entry for the global “+” and the Home Screen quick action.
/// The client is a visible field, so the user does not have to open a nested
/// menu before reaching the amount and description.
struct NewIncomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(AppModel.self) private var app

    let clients: [Client]
    let month: Date

    @State private var amountText = ""
    @State private var project = ""
    @State private var task = ""
    @State private var selectedClient: Client?
    @State private var date: Date
    @State private var status: EntryStatus = .paid
    @State private var hasHold = false
    @State private var holdDate = Date()
    @State private var saveError: String?
    @State private var currencyCode = ""
    @State private var confirmsDiscard = false
    @FocusState private var amountFocused: Bool

    init(clients: [Client], month: Date = .now) {
        self.clients = clients
        self.month = month
        let initialDate = Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
            ? Date.now : DateFormat.monthStart(of: month)
        _date = State(initialValue: initialDate)
    }

    private var amount: Decimal? { Validation.moneyAmount(from: amountText) }
    private var canSave: Bool {
        amount != nil && selectedClient?.isInvalidated == false
            && !Validation.trimmed(task, max: Limits.maxTaskLength).isEmpty
    }

    private var hasDraft: Bool { !amountText.isEmpty || !project.isEmpty || !task.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                amountSection
                detailsSection
                scheduleSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .alert("Discard this draft?", isPresented: $confirmsDiscard) {
            Button("Discard draft", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .sheetEditorHeader("Add income", saveEnabled: canSave,
                           onCancel: { if hasDraft { confirmsDiscard = true } else { dismiss() } }, onSave: save)
        .onAppear {
            if selectedClient == nil, clients.count == 1 { selectedClient = clients.first }
            if currencyCode.isEmpty { currencyCode = app.baseCurrencyCode }
            holdDate = date
            amountFocused = true
        }
        .onChange(of: date) { _, value in
            if holdDate < value { holdDate = value }
        }
        .saveErrorAlert($saveError, title: "Could not save line")
        .interactiveDismissDisabled(hasDraft)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .accessibilityIdentifier("composer.newIncome")
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("Amount")
            ChromeCard {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Menu {
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(AppModel.supportedCurrencyCodes, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Text(currencyCode.isEmpty ? app.baseCurrencyCode : currencyCode).font(.body)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Currency")
                    .accessibilityValue(currencyCode)
                    TextField("0", text: $amountText)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($amountFocused)
                        .submitLabel(.next)
                        .accessibilityLabel("Amount")
                        .accessibilityIdentifier("composer.newIncome.amount")
                }
                .appFont(34, .bold, design: .rounded, relativeTo: .title)
                .monospacedDigit()
                .padding(16)
                if !amountText.isEmpty && amount == nil {
                    Text("Enter a positive amount with at most two decimal places.")
                        .font(.caption)
                        .foregroundStyle(Theme.statusProgress)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("Details")
            ChromeCard {
                ChromeRow(icon: "person.crop.circle") {
                    Picker("Client", selection: $selectedClient) {
                        Text("Choose").tag(Optional<Client>.none)
                        ForEach(clients.filter { !$0.isInvalidated }) { client in
                            Text(client.name).tag(Optional(client))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("composer.newIncome.client")
                }
                ChromeDivider()
                ChromeRow(icon: "folder") {
                    TextField("Project", text: $project)
                        .onChange(of: project) { _, value in
                            project = Validation.capped(value, max: Limits.maxProjectLength)
                        }
                        .accessibilityLabel("Project")
                }
                ChromeDivider()
                ChromeRow(icon: "text.document", alignTop: true) {
                    TextField("Describe the work", text: $task, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.vertical, 12)
                        .onChange(of: task) { _, value in
                            task = Validation.capped(value, max: Limits.maxTaskLength)
                        }
                        .accessibilityLabel("Task")
                        .accessibilityIdentifier("composer.newIncome.task")
                }
                ChromeDivider()
                ChromeRow(icon: "checkmark.circle") {
                    Picker("Status", selection: $status) {
                        ForEach(EntryStatus.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("Schedule")
            ChromeCard {
                ChromeRow(icon: "calendar") {
                    Text("Date")
                    Spacer()
                    DatePicker("Income date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                ChromeDivider()
                ChromeRow(icon: "hourglass") {
                    Toggle("Hold until", isOn: $hasHold.animation())
                }
                if hasHold {
                    ChromeDivider()
                    ChromeRow(icon: "calendar.badge.clock") {
                        Text("Hold date")
                        Spacer()
                        DatePicker("Hold date", selection: $holdDate, in: date..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private func save() {
        guard let amount, let client = selectedClient, !client.isInvalidated else { return }
        let cleanTask = Validation.trimmed(task, max: Limits.maxTaskLength)
        guard !cleanTask.isEmpty else { return }
        let cleanProject = Validation.trimmed(project, max: Limits.maxProjectLength)
        let clientID = client.id
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.client?.id == clientID },
            sortBy: [SortDescriptor(\Entry.sortIndex, order: .forward)]
        )
        descriptor.fetchLimit = 1
        do {
            let firstIndex = try context.fetch(descriptor).first?.sortIndex ?? 0
            let entry = Entry(amount: amount,
                              currencyCode: currencyCode,
                              project: cleanProject.isEmpty ? nil : cleanProject,
                              task: cleanTask,
                              date: date,
                              holdUntil: hasHold ? holdDate : nil,
                              status: status,
                              sortIndex: firstIndex - 1)
            entry.client = client
            context.insert(entry)
            if let error = mutations.save(context) {
                saveError = error
            } else {
                dismiss()
            }
        } catch {
            saveError = String(localized: "Could not read this client's existing lines. Your new line was not added.")
        }
    }
}
