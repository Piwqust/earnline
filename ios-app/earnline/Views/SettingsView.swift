import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [Client]
    @Query private var entries: [Entry]
    @Query private var headings: [Heading]
    @Query private var tombstones: [SyncTombstone]

    @State private var saveError: String?
    private let currencies = AppModel.supportedCurrencyCodes

    var body: some View {
        @Bindable var app = appModel
        NavigationStack {
            Form {
                Section {
                    Picker("Primary", selection: $app.baseCurrencyCode) {
                        ForEach(currencies, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    Picker("Secondary", selection: $app.secondaryCurrencyCode) {
                        ForEach(currencies.filter { $0 != app.baseCurrencyCode }, id: \.self) {
                            Text(label(for: $0)).tag($0)
                        }
                    }
                    if unsupportedCurrencyCount > 0 {
                        Label("\(unsupportedCurrencyCount) line\(unsupportedCurrencyCount == 1 ? "" : "s") in an unsupported currency — counted at par (1:1).",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: { Text("Currency") } footer: {
                    Text("Amounts are written in the primary currency. The secondary value is shown alongside totals. Only the primary and secondary currencies are converted; lines in any other currency are summed at par.")
                }

                Section {
                    HStack {
                        Text("1 \(app.baseCurrencyCode)")
                        Spacer()
                        TextField("Rate", value: $app.rate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text(app.secondaryCurrencyCode)
                            .foregroundStyle(Theme.label(0.5))
                    }
                    Stepper("Adjust rate", value: $app.rate, in: 0.01...100000, step: 1)
                        .labelsHidden()
                } header: { Text("Exchange rate") } footer: {
                    Text("Example: \(CurrencyFormatter.string(100, code: app.baseCurrencyCode)) = \(app.secondaryString(100))")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Made with", value: "Liquid Glass")
                } header: { Text("About") }

                Section {
                    TextField("Project URL", text: $app.supabaseURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Publishable key", text: $app.supabaseKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Workspace ID", text: $app.workspaceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { Text("Supabase") } footer: {
                    Text("Personal no-login sync uses this publishable key. Never paste a service_role key into the app.")
                }

                Section {
                    LabeledContent("Mode", value: "Personal")
                    LabeledContent("Workspace", value: app.workspaceID.isEmpty ? "Not set" : app.workspaceID)
                    LabeledContent("Status", value: app.syncMessage)
                    LabeledContent("Pending", value: "\(pendingSyncCount)")
                    if let lastSyncAt = app.lastSyncAt {
                        LabeledContent("Last sync", value: DateFormat.dotted(lastSyncAt))
                    }
                    if let syncError = app.syncError, !syncError.isEmpty {
                        Text(syncError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button(app.isSyncing ? "Syncing..." : "Sync now") {
                        Task { await app.syncNow(context: context) }
                    }
                    .disabled(app.isSyncing || !app.isSupabaseConfigured)
                    Button("Import sample ledger", action: importSampleLedger)
                } header: { Text("Sync") } footer: {
                    Text("This syncs directly to the shared Earnline workspace without an account.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .alert("Could not save changes", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Try again.")
        }
    }

    private func label(for code: String) -> String {
        "\(code)  \(CurrencyFormatter.symbol(for: code))"
    }

    private var pendingSyncCount: Int {
        clients.filter(\.needsSync).count
            + entries.filter(\.needsSync).count
            + headings.filter(\.needsSync).count
            + tombstones.count
    }

    private var unsupportedCurrencyCount: Int {
        entries.filter { !appModel.canConvert($0.currencyCode) }.count
    }

    private func importSampleLedger() {
        do {
            let inserted = try IncomeLedgerImporter.importBundledLedger(into: context)
            if inserted > 0 { appModel.queueSync(context: context) }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
