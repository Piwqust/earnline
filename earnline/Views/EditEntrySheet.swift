import SwiftUI
import SwiftData

struct EditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Bindable var entry: Entry
    let clients: [Client]

    @State private var amountText: String = ""
    @State private var project: String = ""
    @State private var task: String = ""
    @State private var currencyCode = "USD"
    @State private var date: Date = .now
    @State private var hasHold = false
    @State private var holdDate: Date = .now
    @State private var status: EntryStatus = .paid
    @State private var selectedClient: Client?
    @State private var saveError: String?

    @FocusState private var amountFocused: Bool

    private var amountDecimal: Decimal? {
        guard let d = LineParser.decimal(from: amountText), d > 0 else { return nil }
        return Validation.clampAmount(d)
    }
    private var canSave: Bool {
        amountDecimal != nil
            && selectedClient != nil
            && !Validation.trimmed(task, max: Limits.maxTaskLength).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    amountHero
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)

                Section {
                    statusPills
                } header: {
                    Text("Status")
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)

                Section("Details") {
                    fieldRow("folder") {
                        TextField("Project", text: $project)
                            .onChange(of: project) { _, v in project = Validation.capped(v, max: Limits.maxProjectLength) }
                    }
                    fieldRow("text.alignleft", alignTop: true) {
                        TextField("Task", text: $task, axis: .vertical)
                            .lineLimit(1...4)
                            .onChange(of: task) { _, v in task = Validation.capped(v, max: Limits.maxTaskLength) }
                    }
                    Picker(selection: $selectedClient) {
                        ForEach(clients) { Text($0.name).tag(Optional($0)) }
                    } label: {
                        rowLabel("person.crop.circle", "Client")
                    }
                }

                Section("Schedule") {
                    DatePicker(selection: $date, displayedComponents: .date) {
                        rowLabel("calendar", "Date")
                    }
                    Toggle(isOn: $hasHold.animation()) {
                        rowLabel("hourglass", "Hold until")
                    }
                    if hasHold {
                        DatePicker(selection: $holdDate, in: date..., displayedComponents: .date) {
                            rowLabel("calendar.badge.clock", "Hold date")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: date) { _, newValue in
            if holdDate < newValue { holdDate = newValue }
        }
        .alert("Could not save line", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Try again.")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }

    // MARK: Amount hero

    private var amountHero: some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(AppModel.supportedCurrencyCodes, id: \.self) { code in
                    Button { currencyCode = code } label: {
                        Text("\(CurrencyFormatter.symbol(for: code))  \(code)")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(currencyCode)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.label(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.label(0.06), in: .capsule)
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.symbol(for: currencyCode))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.label(0.5))
                TextField("0", text: $amountText)
                    .font(.system(size: 46, weight: .bold))
                    .monospacedDigit()
                    .keyboardType(.numbersAndPunctuation)
                    .fixedSize()
                    .focused($amountFocused)
                    .foregroundStyle(amountDecimal == nil ? Theme.label(0.25) : Theme.label)
                    .onChange(of: amountText) { _, v in amountText = Validation.sanitizeAmountInput(v) }
            }

            Text(secondaryHint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.label(0.4))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: secondaryHint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.label(0.05), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 18))
        .onTapGesture { amountFocused = true }
    }

    /// Live "≈ secondary currency" preview, echoing the ledger's dual-currency display.
    private var secondaryHint: String {
        guard let amount = amountDecimal else { return "Enter an amount" }
        let base = app.toBase(amount, code: currencyCode)
        return "≈ \(app.secondaryString(base))"
    }

    // MARK: Status pills

    private var statusPills: some View {
        HStack(spacing: 8) {
            ForEach(EntryStatus.allCases) { s in
                let selected = status == s
                Button {
                    withAnimation(.snappy(duration: 0.25)) { status = s }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: s.symbol)
                            .font(.system(size: 13, weight: .semibold))
                        Text(s.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selected ? .white : s.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        Capsule().fill(selected ? s.tint : s.tint.opacity(0.12))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Row helpers

    private func rowLabel(_ systemImage: String, _ title: String) -> some View {
        HStack(spacing: 11) {
            leadingIcon(systemImage)
            Text(title).foregroundStyle(Theme.label)
        }
    }

    private func fieldRow(_ systemImage: String,
                          alignTop: Bool = false,
                          @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: alignTop ? .top : .center, spacing: 11) {
            leadingIcon(systemImage)
            content()
        }
    }

    private func leadingIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.label(0.55))
            .frame(width: 26, height: 26)
            .background(Theme.label(0.06), in: .rect(cornerRadius: 7))
    }

    // MARK: Data

    private func load() {
        amountText = NSDecimalNumber(decimal: entry.amount).stringValue
        currencyCode = entry.currencyCode
        project = entry.project ?? ""
        task = entry.task
        date = entry.date
        status = entry.status
        if let h = entry.holdUntil { hasHold = true; holdDate = h }
        selectedClient = entry.client
    }

    private func save() {
        guard let amount = amountDecimal else { return }
        entry.amount = amount
        entry.currencyCode = currencyCode
        let p = Validation.trimmed(project, max: Limits.maxProjectLength)
        entry.project = p.isEmpty ? nil : p
        entry.task = Validation.trimmed(task, max: Limits.maxTaskLength)
        entry.date = date
        entry.holdUntil = hasHold ? holdDate : nil
        entry.status = status
        if let c = selectedClient { entry.client = c }
        entry.markDirty()
        do {
            try context.save()
            app.queueSync(context: context)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
