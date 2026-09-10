import SwiftUI
import SwiftData

/// Paste a block of text (as if from Notes) and turn each line into an income
/// line for one client. Parsing reuses `LineParser.parseBlock`; the live preview
/// shows which rows will commit and which are skipped. Chrome follows the
/// ChatGPT "Report bug" sheet: title + ✕, labeled input cards, black pill CTA.
struct PasteLinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(LedgerMutationStore.self) private var mutations

    let clients: [Client]
    var defaultClient: Client?
    var sharedText: String?

    @State private var text = ""
    @State private var selectedClient: Client?
    @State private var saveError: String?
    @State private var successFeedback = 0

    private var drafts: [ParsedLine] {
        LineParser.parseLedgerBlock(text, defaultCurrency: app.baseCurrencyCode)
    }
    private var validDrafts: [ParsedLine] { drafts.filter(\.isCommittable) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeader("Add to")
                    ChromeCard {
                        ChromeRow(icon: "person.crop.circle") {
                            Text("Client").foregroundStyle(Theme.label)
                            Spacer()
                            clientMenu
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    CardHeader("Paste lines")
                    ChromeCard {
                        TextEditor(text: $text)
                            .appFont(16)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Lines to import")
                    }
                    CardFootnote {
                        // swiftlint:disable:next line_length
                        Text("One income line per row — e.g. \u{201C}+$240 Project: task\u{201D}. A heading like \u{201C}— Income for April\u{201D} dates the lines under it to that month. Rows without an amount are skipped.")
                    }
                }

                if !drafts.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        CardHeader(verbatim: String(localized: "Preview — \(validDrafts.count) of \(drafts.count) will be added"))
                        ChromeCard {
                            ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                                draftRow(draft)
                                if index < drafts.count - 1 {
                                    ChromeDivider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .sheetHeader("Paste lines", onClose: { dismiss() })
        .sheetFooter {
            PillCTA("Add \(validDrafts.count)",
                    isEnabled: !validDrafts.isEmpty && selectedClient != nil,
                    action: commit)
        }
        .onAppear {
            if text.isEmpty, let sharedText { text = sharedText }
            if selectedClient == nil { selectedClient = defaultClient ?? clients.first }
        }
        .saveErrorAlert($saveError, title: "Could not import lines")
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .sensoryFeedback(.success, trigger: successFeedback)
    }

    /// Client picker with a truncating label — long names shorten instead of
    /// wrapping the row. Menu content stays a native inline picker.
    private var clientMenu: some View {
        Menu {
            Picker("Client", selection: $selectedClient) {
                ForEach(clients) { client in
                    Text(client.name).tag(Optional(client))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(selectedClient?.name ?? String(localized: "Choose"))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Client")
        .accessibilityValue(selectedClient?.name ?? "")
    }

    @ViewBuilder
    private func draftRow(_ draft: ParsedLine) -> some View {
        let valid = draft.isCommittable
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(valid ? Theme.statusPaid : Theme.statusProgress)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let amount = draft.amount {
                        Text(CurrencyFormatter.string(amount, code: draft.currencyCode))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(describe(draft))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let date = draft.date {
                    Text(DateFormat.month(date))
                        .appFont(14)
                        .foregroundStyle(.tertiary)
                }
                if !valid {
                    Text("No amount — will be skipped")
                        .appFont(14)
                        .foregroundStyle(Theme.statusProgress)
                }
            }
            Spacer(minLength: 0)
        }
        .appFont(15)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func describe(_ draft: ParsedLine) -> String {
        [draft.project, draft.task.isEmpty ? nil : draft.task]
            .compactMap { $0 }
            .joined(separator: " : ")
    }

    private func commit() {
        guard let client = selectedClient else { return }
        let minIndex = client.entries.map(\.sortIndex).min() ?? 0
        for (offset, draft) in validDrafts.enumerated() {
            guard let amount = draft.amount else { continue }
            let project = draft.project.map { Validation.trimmed($0, max: Limits.maxProjectLength) }
            let entry = Entry(
                amount: Validation.clampAmount(amount),
                currencyCode: draft.currencyCode,
                project: (project?.isEmpty == false) ? project : nil,
                task: Validation.trimmed(draft.task, max: Limits.maxTaskLength),
                date: draft.date ?? .now,
                holdUntil: draft.holdUntil,
                status: draft.status ?? .paid,
                sortIndex: minIndex - 1 - offset
            )
            entry.client = client
            context.insert(entry)
        }
        if let error = mutations.save(context) {
            // `LedgerMutationStore.save` rolls the entire failed transaction back.
            saveError = error
        } else {
            if let sharedText { LedgerSystemSurfaces.consumeSharedText(sharedText) }
            successFeedback += 1
            dismiss()
        }
    }
}
