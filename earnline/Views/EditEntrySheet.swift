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
    @State private var date: Date = .now
    @State private var hasHold = false
    @State private var holdDate: Date = .now
    @State private var status: EntryStatus = .paid
    @State private var selectedClient: Client?

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
                Section("Amount") {
                    HStack {
                        Text(CurrencyFormatter.symbol(for: entry.currencyCode))
                            .foregroundStyle(Theme.label(0.5))
                        TextField("0", text: $amountText)
                            .keyboardType(.numbersAndPunctuation)
                            .onChange(of: amountText) { _, v in amountText = Validation.sanitizeAmountInput(v) }
                    }
                }
                Section("Details") {
                    TextField("Project", text: $project)
                        .onChange(of: project) { _, v in project = Validation.capped(v, max: Limits.maxProjectLength) }
                    TextField("Task", text: $task, axis: .vertical)
                        .lineLimit(1...4)
                        .onChange(of: task) { _, v in task = Validation.capped(v, max: Limits.maxTaskLength) }
                    Picker("Client", selection: $selectedClient) {
                        ForEach(clients) { Text($0.name).tag(Optional($0)) }
                    }
                }
                Section("Status & dates") {
                    Picker("Status", selection: $status) {
                        ForEach(EntryStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Hold until", isOn: $hasHold.animation())
                    if hasHold {
                        DatePicker("Hold date", selection: $holdDate, in: date..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: date) { _, newValue in
            if holdDate < newValue { holdDate = newValue }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    private func load() {
        amountText = NSDecimalNumber(decimal: entry.amount).stringValue
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
        let p = Validation.trimmed(project, max: Limits.maxProjectLength)
        entry.project = p.isEmpty ? nil : p
        entry.task = Validation.trimmed(task, max: Limits.maxTaskLength)
        entry.date = date
        entry.holdUntil = hasHold ? holdDate : nil
        entry.status = status
        if let c = selectedClient { entry.client = c }
        entry.markDirty()
        try? context.save()
        app.queueSync(context: context)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}
