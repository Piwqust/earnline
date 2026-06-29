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

    private let currencies = ["USD", "EUR", "GBP", "RUB", "UAH"]
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        @Bindable var app = appModel
        NavigationStack {
            Form {
                Section {
                    Picker("Primary", selection: $app.baseCurrencyCode) {
                        ForEach(currencies, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    Picker("Secondary", selection: $app.secondaryCurrencyCode) {
                        ForEach(currencies, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                } header: { Text("Currency") } footer: {
                    Text("Amounts are written in the primary currency. The secondary value is shown alongside totals.")
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
                } header: { Text("Supabase") } footer: {
                    Text("Use a publishable key. Never paste a service_role key into the app.")
                }

                Section {
                    if let signedInEmail = app.signedInEmail {
                        LabeledContent("Signed in", value: signedInEmail)
                        Button("Sign out") { Task { await app.signOut() } }
                    } else {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                        HStack {
                            Button("Sign in") { Task { await app.signIn(email: email, password: password) } }
                                .disabled(!canSubmitAuth)
                            Spacer()
                            Button("Create account") { Task { await app.signUp(email: email, password: password) } }
                                .disabled(!canSubmitAuth)
                        }
                    }
                } header: { Text("Account") }

                Section {
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
                    Button("Import bundled ledger") {
                        let inserted = IncomeLedgerImporter.importBundledLedger(into: context)
                        if inserted > 0 { app.queueSync(context: context) }
                    }
                } header: { Text("Sync") }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func label(for code: String) -> String {
        "\(code)  \(CurrencyFormatter.symbol(for: code))"
    }

    private var canSubmitAuth: Bool {
        appModel.isSupabaseConfigured
            && email.contains("@")
            && password.count >= 6
    }

    private var pendingSyncCount: Int {
        clients.filter(\.needsSync).count
            + entries.filter(\.needsSync).count
            + headings.filter(\.needsSync).count
            + tombstones.count
    }
}
