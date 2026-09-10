import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LedgerBackupTransferRoute: String, Identifiable {
    case export
    case `import`

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .export: "Export backup"
        case .import: "Import backup"
        }
    }
}

/// Native document-picker flow for the complete, versioned JSON backup. The
/// import path is merge-only: it never deletes or overwrites current rows.
struct LedgerBackupTransferView: View {
    @Environment(AppModel.self) private var app
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let route: LedgerBackupTransferRoute

    @State private var exportDocument: LedgerBackupDocument?
    @State private var presentsFileExporter = false
    @State private var presentsFileImporter = false
    @State private var preview: LedgerBackup?
    @State private var importPlan: LedgerBackup.ImportSummary?
    @State private var importedFilename: String?
    @State private var confirmsImport = false
    @State private var importedSummary: LedgerBackup.ImportSummary?
    @State private var saveError: String?
    @State private var inspectionTask: Task<Void, Never>?
    @State private var isInspecting = false

    var body: some View {
        NavigationStack {
            Form {
                switch route {
                case .export:
                    exportContent
                case .import:
                    importContent
                }
            }
            .navigationTitle(route.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
            }
        }
        .fileExporter(
            isPresented: $presentsFileExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Earnline backup"
        ) { result in
            if case let .failure(error) = result {
                saveError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $presentsFileImporter,
            allowedContentTypes: [.json, .data]
        ) { result in
            inspectImportedFile(result)
        }
        .confirmationDialog(
            "Import this backup?",
            isPresented: $confirmsImport,
            titleVisibility: .visible
        ) {
            Button("Import backup") { commitImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing rows stay unchanged. New rows are added as local changes and can sync to this workspace.")
        }
        .alert(
            "Backup imported",
            isPresented: Binding(
                get: { importedSummary != nil },
                set: { if !$0 { importedSummary = nil } }
            )
        ) {
            Button("Done") { dismiss() }
        } message: {
            if let importedSummary {
                Text("Added \(importedSummary.inserted) record(s). Skipped \(importedSummary.skippedExisting) record(s) already present.")
            }
        }
        .saveErrorAlert($saveError, title: "Could not transfer backup")
        .onDisappear { inspectionTask?.cancel() }
    }

    @ViewBuilder
    private var exportContent: some View {
        Section {
            Button(action: prepareExport) {
                Label("Export full backup", systemImage: "externaldrive.badge.plus")
            }
            .accessibilityIdentifier("settings.backup.export")
        } footer: {
            Text("Includes clients, income lines, event notes, project icons, month reviews, and currency settings. "
                 + "Sync tombstones are excluded so an old backup cannot delete current cloud data.")
        }

        Section("Format") {
            LabeledContent("Type", value: "Versioned JSON")
            Text("Keep the file in a secure place. It contains your financial data in readable form.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var importContent: some View {
        Section {
            Button {
                presentsFileImporter = true
            } label: {
                Label("Choose backup file", systemImage: "folder")
            }
            .disabled(isInspecting)
            .accessibilityIdentifier("settings.backup.import")
            if isInspecting { ProgressView("Reading backup") }
        } footer: {
            Text("The backup is checked completely before the ledger changes. "
                 + "Import adds missing records and never overwrites rows already in this workspace.")
        }

        if let preview {
            Section("Preview") {
                if let importedFilename {
                    LabeledContent("File", value: importedFilename)
                }
                LabeledContent("Workspace in file", value: preview.workspaceID)
                LabeledContent("Currencies in file",
                               value: "\(preview.settings.baseCurrencyCode) / \(preview.settings.secondaryCurrencyCode)")
                LabeledContent("Rate in file") {
                    Text(verbatim: "1 \(preview.settings.baseCurrencyCode) = "
                         + "\(preview.settings.exchangeRate) \(preview.settings.secondaryCurrencyCode)")
                }
                LabeledContent("Current currencies", value: "\(app.baseCurrencyCode) / \(app.secondaryCurrencyCode)")
                LabeledContent("Current rate", value: "1 \(app.baseCurrencyCode) = \(app.rate.formatted()) \(app.secondaryCurrencyCode)")
                LabeledContent("Records", value: "\(preview.totalRecords)")
                LabeledContent("Clients", value: "\(preview.clients.count)")
                LabeledContent("Income lines", value: "\(preview.entries.count)")
                LabeledContent("Notes", value: "\(preview.headings.count)")
                LabeledContent("Project icons", value: "\(preview.projectIcons.count)")
                LabeledContent("Month reviews", value: "\(preview.monthReviews.count)")
            }

            Section {
                if let importPlan {
                    LabeledContent("New records", value: "\(importPlan.inserted)")
                        .accessibilityIdentifier("settings.backup.newRecords")
                    LabeledContent("Already in the ledger", value: "\(importPlan.skippedExisting)")
                }
                Button("Import \(importPlan?.inserted ?? preview.totalRecords) records") {
                    confirmsImport = true
                }
                .disabled((importPlan?.inserted ?? preview.totalRecords) == 0)
                .accessibilityIdentifier("settings.backup.confirmImport")
            } footer: {
                // swiftlint:disable:next line_length
                Text("Only records missing from the current ledger are added. Currency settings are shown for provenance but are not applied automatically to the current workspace.")
            }
        }
    }

    private func prepareExport() {
        do {
            exportDocument = LedgerBackupDocument(data: try LedgerBackupCodec.export(context: context, app: app))
            presentsFileExporter = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func inspectImportedFile(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else {
            if case let .failure(error) = result { saveError = error.localizedDescription }
            return
        }
        inspectionTask?.cancel()
        isInspecting = true
        preview = nil
        importPlan = nil
        inspectionTask = Task {
            defer { isInspecting = false }
            do {
                let data = try await LedgerImportFile.readInBackground(url)
                try Task.checkCancellation()
                let decoded = try LedgerBackupCodec.decode(data)
                preview = decoded
                importPlan = try LedgerBackupCodec.importPlan(decoded, into: context)
                importedFilename = url.lastPathComponent
            } catch {
                guard !Task.isCancelled else { return }
                saveError = error.localizedDescription
            }
        }
    }

    private func commitImport() {
        guard let preview else { return }
        do {
            let summary = try LedgerBackupCodec.importBackup(preview, into: context)
            guard summary.inserted > 0 else {
                importedSummary = summary
                return
            }
            if let error = mutations.save(context) {
                saveError = error
            } else {
                importedSummary = summary
            }
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}

private struct LedgerBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
