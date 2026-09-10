import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The normal Settings → Data routes. CSV intentionally lives outside
/// Developer Mode: it is a small, explicit ledger interchange tool, not a
/// workspace backup or a sync-recovery control.
enum CSVTransferRoute: String, Identifiable {
    case exportLedger
    case importLedger

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .exportLedger: "Export CSV"
        case .importLedger: "Import CSV"
        }
    }
}

/// Native file-picker flow for the deliberately narrow ledger CSV format.
/// Validation completes before the transaction is touched; the eventual one
/// context save makes the selected rows plus any confirmed new clients atomic.
struct CSVTransferView: View {
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    let route: CSVTransferRoute

    @State private var exportDocument: LedgerCSVDocument?
    @State private var presentsFileExporter = false
    @State private var presentsFileImporter = false
    @State private var preview: LedgerCSV.Preview?
    @State private var importedFilename: String?
    @State private var saveError: String?
    @State private var confirmsNewClients = false
    @State private var completedImportCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                switch route {
                case .exportLedger:
                    exportContent
                case .importLedger:
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
            contentType: .commaSeparatedText,
            defaultFilename: "Earnline ledger"
        ) { result in
            if case let .failure(error) = result {
                saveError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $presentsFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            inspectImportedFile(result)
        }
        .confirmationDialog(
            "Create \(unknownClientNames.count) new client\(unknownClientNames.count == 1 ? "" : "s")?",
            isPresented: $confirmsNewClients,
            titleVisibility: .visible
        ) {
            Button("Create and import") { commitImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(unknownClientNames.joined(separator: ", "))
        }
        .alert(
            "CSV imported",
            isPresented: Binding(
                get: { completedImportCount != nil },
                set: { if !$0 { completedImportCount = nil } }
            )
        ) {
            Button("Done") { dismiss() }
        } message: {
            Text("Imported \(completedImportCount ?? 0) income line(s).")
        }
        .saveErrorAlert($saveError, title: "Could not transfer CSV")
    }

    @ViewBuilder
    private var exportContent: some View {
        Section {
            Button(action: prepareExport) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("settings.csv.export")
        } footer: {
            // swiftlint:disable:next line_length
            Text("Exports ledger income lines only: date, client, project, task, original amount, currency, status, and hold date. This is not a backup and does not include notes, settings, or sync IDs.")
        }

        Section("Included") {
            LabeledContent("Income lines", value: "\(liveEntries.count)")
            Text("UTF-8 · RFC 4180")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var importContent: some View {
        Section {
            Button {
                presentsFileImporter = true
            } label: {
                Label("Choose CSV file", systemImage: "folder")
            }
            .accessibilityIdentifier("settings.csv.import")
        } footer: {
            // swiftlint:disable:next line_length
            Text("Review every row before importing. Invalid rows and duplicates stop the whole import; unknown clients are created only after you confirm.")
        }

        if let preview {
            Section("Preview") {
                if let importedFilename {
                    LabeledContent("File", value: importedFilename)
                }
                LabeledContent("Valid rows", value: "\(preview.rows.count)")
                LabeledContent("Errors", value: "\(preview.issues.count)")
                LabeledContent("Duplicates", value: "\(preview.duplicateRowNumbers.count)")
                if !unknownClientNames.isEmpty {
                    LabeledContent("New clients", value: "\(unknownClientNames.count)")
                }
            }

            if !preview.issues.isEmpty {
                Section("Errors") {
                    ForEach(preview.issues) { issue in
                        Label {
                            Text(issue.rowNumber.map { "Row \($0): \(issue.message)" } ?? issue.message)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.statusCanceled)
                        }
                    }
                }
            }

            if !preview.duplicateRowNumbers.isEmpty {
                Section {
                    ForEach(preview.rows.filter { preview.duplicateRowNumbers.contains($0.rowNumber) }) { row in
                        Label {
                            Text("Row \(row.rowNumber): \(row.client) · \(row.task)")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                            .foregroundStyle(Theme.statusProgress)
                        }
                    }
                } header: {
                    Text("Duplicates")
                } footer: {
                    // swiftlint:disable:next line_length
                    Text("Duplicates may already exist in this ledger or appear more than once in this file. Remove them from the CSV and choose the file again.")
                }
            }

            if !preview.rows.isEmpty {
                Section("Rows") {
                    ForEach(preview.rows.prefix(20)) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.client).fontWeight(.medium)
                                Spacer()
                                Text(CurrencyFormatter.string(row.amount, code: row.currencyCode))
                                    .monospacedDigit()
                            }
                            Text([row.project, row.task].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            Text("\(DateFormat.dotted(row.date)) · \(row.status.title)")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if preview.rows.count > 20 {
                        Text("Showing the first 20 of \(preview.rows.count) rows.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(action: requestImport) {
                    Label("Import \(preview.rows.count) rows", systemImage: "square.and.arrow.down")
                }
                .disabled(!preview.isReadyToImport)
                .accessibilityIdentifier("settings.csv.confirmImport")
            } footer: {
                if preview.isReadyToImport {
                    Text("All selected rows will be saved together, or none will be saved if the ledger cannot be updated.")
                } else {
                    Text("Fix the listed errors and duplicates before importing. Nothing has been changed in your ledger.")
                }
            }
        }
    }

    private var liveEntries: [Entry] {
        entries.filter { !$0.isDeleted }
    }

    private var unknownClientNames: [String] {
        guard let preview else { return [] }
        let known = Set(clients.filter { !$0.isDeleted }.map { LedgerCSV.clientKey($0.name) })
        var seen: Set<String> = []
        return preview.rows.compactMap { row in
            let key = LedgerCSV.clientKey(row.client)
            guard !known.contains(key), seen.insert(key).inserted else { return nil }
            return row.client
        }
    }

    private func prepareExport() {
        let records = liveEntries.map(LedgerCSV.exportRecord)
        exportDocument = LedgerCSVDocument(data: LedgerCSV.export(records))
        presentsFileExporter = true
    }

    private func inspectImportedFile(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else {
            if case let .failure(error) = result { saveError = error.localizedDescription }
            return
        }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try LedgerImportFile.read(url)
            let existingKeys = Set(liveEntries.compactMap { entry -> LedgerCSV.DuplicateKey? in
                guard let client = entry.client, !client.isDeleted else { return nil }
                return LedgerCSV.DuplicateKey(
                    date: entry.date,
                    client: client.name,
                    project: entry.project,
                    task: entry.task,
                    amount: entry.amount,
                    currencyCode: entry.currencyCode,
                    status: entry.status,
                    holdDate: entry.holdUntil
                )
            })
            preview = LedgerCSV.preview(data, existingKeys: existingKeys)
            importedFilename = url.lastPathComponent
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func requestImport() {
        guard preview?.isReadyToImport == true else { return }
        if unknownClientNames.isEmpty {
            commitImport()
        } else {
            confirmsNewClients = true
        }
    }

    private func commitImport() {
        guard let preview, preview.isReadyToImport else { return }
        var clientsByKey: [String: Client] = [:]
        for client in clients where !client.isDeleted {
            // A legacy store may contain two visually equivalent names. Keep
            // its first existing client rather than crashing an import solely
            // because a historical duplicate predates this validation flow.
            clientsByKey[LedgerCSV.clientKey(client.name), default: client] = client
        }
        var nextClientSortIndex = (clients.map(\.sortIndex).max() ?? -1) + 1
        var sortIndexByClientAndMonth: [String: Int] = [:]

        for entry in liveEntries {
            guard let client = entry.client else { continue }
            let key = sortKey(clientID: client.id, date: entry.date)
            sortIndexByClientAndMonth[key] = max(sortIndexByClientAndMonth[key, default: -1], entry.sortIndex)
        }

        for row in preview.rows {
            let clientKey = LedgerCSV.clientKey(row.client)
            let client: Client
            if let existing = clientsByKey[clientKey] {
                client = existing
            } else {
                client = Client(
                    name: row.client,
                    colorHex: Theme.clientPalette[nextClientSortIndex % Theme.clientPalette.count],
                    sortIndex: nextClientSortIndex
                )
                nextClientSortIndex += 1
                context.insert(client)
                clientsByKey[clientKey] = client
            }

            let key = sortKey(clientID: client.id, date: row.date)
            let sortIndex = sortIndexByClientAndMonth[key, default: -1] + 1
            sortIndexByClientAndMonth[key] = sortIndex
            let entry = Entry(
                amount: row.amount,
                currencyCode: row.currencyCode,
                project: row.project,
                task: row.task,
                date: row.date,
                holdUntil: row.holdDate,
                status: row.status,
                sortIndex: sortIndex
            )
            entry.client = client
            context.insert(entry)
        }

        if let error = mutations.save(context) {
            saveError = error
        } else {
            completedImportCount = preview.rows.count
        }
    }

    private func sortKey(clientID: UUID, date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(clientID.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)"
    }
}

private struct LedgerCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

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
