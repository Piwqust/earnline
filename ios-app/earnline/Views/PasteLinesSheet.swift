import SwiftUI
import SwiftData

/// Paste a block of text (as if from Notes) and turn each line into an income
/// line for one client. Parsing reuses `LineParser.parseBlock`; the live preview
/// shows which rows will commit and which are skipped.
struct PasteLinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    let clients: [Client]
    var defaultClient: Client?

    @State private var text = ""
    @State private var selectedClient: Client?
    @State private var saveError: String?

    private var drafts: [ParsedLine] {
        LineParser.parseBlock(text, defaultCurrency: app.baseCurrencyCode)
    }
    private var validDrafts: [ParsedLine] { drafts.filter(\.isCommittable) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Client", selection: $selectedClient) {
                        ForEach(clients) { Text($0.name).tag(Optional($0)) }
                    }
                } header: { Text("Add to") }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .font(.system(size: 16))
                        .accessibilityLabel("Lines to import")
                } header: { Text("Paste lines") } footer: {
                    Text("One income line per row — e.g. \u{201C}+$240 Project: task\u{201D}. Each line is parsed; rows without an amount are skipped.")
                }

                if !drafts.isEmpty {
                    Section {
                        ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                            draftRow(draft)
                        }
                    } header: {
                        Text("Preview — \(validDrafts.count) of \(drafts.count) will be added")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Paste lines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(validDrafts.count)", action: commit)
                        .fontWeight(.semibold)
                        .disabled(validDrafts.isEmpty || selectedClient == nil)
                }
            }
            .onAppear {
                if selectedClient == nil { selectedClient = defaultClient ?? clients.first }
            }
        }
        .alert("Could not import lines", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Try again.")
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    @ViewBuilder
    private func draftRow(_ draft: ParsedLine) -> some View {
        let valid = draft.isCommittable
        HStack(spacing: 10) {
            Image(systemName: valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(valid ? Theme.statusPaid : Theme.statusProgress)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let amount = draft.amount {
                        Text(CurrencyFormatter.string(amount, code: draft.currencyCode))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(describe(draft))
                        .foregroundStyle(Theme.label(0.65))
                        .lineLimit(1)
                }
                if !valid {
                    Text("No amount — will be skipped")
                        .font(.caption)
                        .foregroundStyle(Theme.statusProgress)
                }
            }
        }
        .font(.system(size: 15))
    }

    private func describe(_ draft: ParsedLine) -> String {
        [draft.project, draft.task.isEmpty ? nil : draft.task]
            .compactMap { $0 }
            .joined(separator: " : ")
    }

    private func commit() {
        guard let client = selectedClient else { return }
        let minIndex = client.entries.map(\.sortIndex).min() ?? 0
        var inserted: [Entry] = []
        for (offset, draft) in validDrafts.enumerated() {
            guard let amount = draft.amount else { continue }
            let project = draft.project.map { Validation.trimmed($0, max: Limits.maxProjectLength) }
            let entry = Entry(
                amount: Validation.clampAmount(amount),
                currencyCode: draft.currencyCode,
                project: (project?.isEmpty == false) ? project : nil,
                task: Validation.trimmed(draft.task, max: Limits.maxTaskLength),
                holdUntil: draft.holdUntil,
                status: draft.status ?? .paid,
                sortIndex: minIndex - 1 - offset
            )
            entry.client = client
            context.insert(entry)
            inserted.append(entry)
        }
        do {
            try context.save()
            app.queueSync(context: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            inserted.forEach(context.delete)
            saveError = error.localizedDescription
        }
    }
}
