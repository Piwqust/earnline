import Foundation
import SwiftUI

/// A deliberately separate, Debug-only route for people who administer their
/// own Supabase project. The normal Settings screen only surfaces the current
/// connection state; no live sync configuration changes while someone types.
#if DEBUG
struct SupabaseConnectionSettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var projectURL = ""
    @State private var publishableKey = ""
    @State private var isEditingPersonalConnection = false
    @State private var verificationState: VerificationState = .idle
    @State private var pendingAction: PendingAction?
    @State private var didLoadDraft = false

    private enum VerificationState: Equatable {
        case idle
        case checking
        case verified
        case failed(String)
    }

    private enum PendingAction: Identifiable {
        case beginPersonalSetup
        case applyPersonalConnection
        case restoreBuiltInConnection

        var id: String {
            switch self {
            case .beginPersonalSetup: "begin"
            case .applyPersonalConnection: "apply"
            case .restoreBuiltInConnection: "restore"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Current connection") {
                    Text(appModel.isUsingCustomSupabaseConnection ? "Personal database" : "Built-in database")
                        .foregroundStyle(.secondary)
                }
                Text("A personal connection is for a Supabase project you administer. It is separate from everyday ledger settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Connection")
            }

            if !isEditingPersonalConnection {
                Section {
                    Button("Set up a personal Supabase database") {
                        pendingAction = .beginPersonalSetup
                    }
                    .accessibilityIdentifier("supabaseConnection.beginSetup")
                } footer: {
                    Text("You will check the project before Earnline uses it. Nothing changes until you confirm.")
                }
            } else {
                Section {
                    TextField("Project URL", text: $projectURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .accessibilityIdentifier("supabaseConnection.projectURL")

                    TextField("Publishable key", text: $publishableKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("supabaseConnection.publishableKey")
                } header: {
                    Text("Personal database")
                } footer: {
                    // swiftlint:disable:next line_length
                    Text("Use the Project URL and publishable key from your Supabase project. Never paste a service-role or secret key into Earnline.")
                }

                Section {
                    Button {
                        Task { await verifyConnection() }
                    } label: {
                        HStack {
                            Text(verificationState == .checking ? "Checking connection…" : "Check connection")
                            Spacer()
                            if verificationState == .checking {
                                ProgressView()
                            } else if verificationState == .verified {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(verificationState == .checking)
                    .accessibilityIdentifier("supabaseConnection.verify")

                    if case let .failed(message) = verificationState {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Use this database") {
                        pendingAction = .applyPersonalConnection
                    }
                    .disabled(verificationState != .verified)
                    .accessibilityIdentifier("supabaseConnection.apply")
                } footer: {
                    Text("Saving switches the sync client to this project. Your current ledger is not deleted.")
                }

                if appModel.isUsingCustomSupabaseConnection {
                    Section {
                        Button("Return to built-in database", role: .destructive) {
                            pendingAction = .restoreBuiltInConnection
                        }
                        .accessibilityIdentifier("supabaseConnection.restoreBuiltIn")
                    } footer: {
                        Text("This keeps the personal project untouched and reconnects Earnline to its built-in database.")
                    }
                }
            }
        }
        .navigationTitle("Personal Supabase database")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: appModel.workspaceEnvironment) {
            loadDraft()
        }
        .onChange(of: projectURL) { verificationState = .idle }
        .onChange(of: publishableKey) { verificationState = .idle }
        .confirmationDialog(confirmationTitle,
                            isPresented: Binding(
                                get: { pendingAction != nil },
                                set: { if !$0 { pendingAction = nil } }
                            ),
                            titleVisibility: .visible) {
            Button(confirmationButtonTitle, role: confirmationRole) {
                performPendingAction()
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .beginPersonalSetup:
            "Set up a personal database?"
        case .applyPersonalConnection:
            "Use this Supabase project?"
        case .restoreBuiltInConnection:
            "Return to the built-in database?"
        case nil:
            ""
        }
    }

    private var confirmationButtonTitle: String {
        switch pendingAction {
        case .beginPersonalSetup:
            "Continue"
        case .applyPersonalConnection:
            "Use database"
        case .restoreBuiltInConnection:
            "Return to built-in"
        case nil:
            "Continue"
        }
    }

    private var confirmationRole: ButtonRole? {
        pendingAction == .restoreBuiltInConnection ? .destructive : nil
    }

    private var confirmationMessage: String {
        switch pendingAction {
        case .beginPersonalSetup:
            // swiftlint:disable:next line_length
            "Earnline will ask for a Project URL and publishable key, check them, then wait for your final confirmation before changing the active sync project."
        case .applyPersonalConnection:
            // swiftlint:disable:next line_length
            "The active sync client will switch to this project. Earnline does not delete your current local ledger or data in either cloud project."
        case .restoreBuiltInConnection:
            "The personal project remains unchanged. Earnline will only switch its active sync client back to the built-in project."
        case nil:
            ""
        }
    }

    private func loadDraft() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        projectURL = appModel.supabaseURLString
        publishableKey = appModel.supabaseKey
        isEditingPersonalConnection = appModel.isUsingCustomSupabaseConnection
    }

    private func performPendingAction() {
        defer { pendingAction = nil }
        switch pendingAction {
        case .beginPersonalSetup:
            isEditingPersonalConnection = true
            verificationState = .idle
        case .applyPersonalConnection:
            guard case let .valid(url, key) = SupabaseConnectionValidator.validate(projectURL: projectURL,
                                                                                   publishableKey: publishableKey) else {
                verificationState = .failed("Check the project URL and publishable key first.")
                return
            }
            appModel.applyPersonalSupabaseConnection(url: url, publishableKey: key)
        case .restoreBuiltInConnection:
            appModel.restoreBuiltInSupabaseConnection()
            projectURL = appModel.supabaseURLString
            publishableKey = appModel.supabaseKey
            isEditingPersonalConnection = false
            verificationState = .idle
        case nil:
            return
        }
    }

    private func verifyConnection() async {
        switch SupabaseConnectionValidator.validate(projectURL: projectURL, publishableKey: publishableKey) {
        case let .invalid(message):
            verificationState = .failed(message)
        case let .valid(url, key):
            verificationState = .checking
            do {
                try await SupabaseConnectionValidator.verify(projectURL: url, publishableKey: key)
                verificationState = .verified
            } catch let error as LocalizedError {
                verificationState = .failed(error.errorDescription ?? "Could not check this Supabase project.")
            } catch {
                verificationState = .failed("Could not check this Supabase project.")
            }
        }
    }
}
#endif

enum SupabaseConnectionValidator {
    enum ValidationResult: Equatable {
        case valid(URL, String)
        case invalid(String)
    }

    enum VerificationError: LocalizedError {
        case requestRejected
        case unavailable

        var errorDescription: String? {
            switch self {
            case .requestRejected:
                "This project rejected the publishable key. Check that both values belong to the same Supabase project."
            case .unavailable:
                "Could not reach this Supabase project. Check the URL and try again."
            }
        }
    }

    static func validate(projectURL rawURL: String, publishableKey rawKey: String) -> ValidationResult {
        let urlText = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            return .invalid("Enter a valid HTTPS Project URL.")
        }
        guard !key.isEmpty else {
            return .invalid("Enter a publishable key.")
        }
        guard !looksLikeSecretKey(key) else {
            return .invalid("Use a publishable or anon key, never a secret or service-role key.")
        }
        return .valid(url, key)
    }

    private static func looksLikeSecretKey(_ key: String) -> Bool {
        if key.lowercased().hasPrefix("sb_secret_") {
            return true
        }

        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payloadData = base64URLDecoded(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let role = payload["role"] as? String else {
            return false
        }
        return role.lowercased() == "service_role"
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    static func verify(projectURL: URL, publishableKey: String) async throws {
        let endpoint = projectURL
            .appending(path: "auth")
            .appending(path: "v1")
            .appending(path: "settings")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw VerificationError.unavailable
            }
            guard (200 ..< 300).contains(response.statusCode) else {
                throw VerificationError.requestRejected
            }
        } catch let error as VerificationError {
            throw error
        } catch {
            throw VerificationError.unavailable
        }
    }
}

extension AppModel {
    var isUsingCustomSupabaseConnection: Bool {
        let bundled = workspaceEnvironment.defaultSupabaseConfig
        return supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines) != bundled.url
            || supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines) != bundled.publishableKey
    }

    /// The caller already verified the draft. Updating both values together
    /// prevents a partly typed URL or key from restarting realtime/sync.
    func applyPersonalSupabaseConnection(url: URL, publishableKey: String) {
        supabaseURLString = url.absoluteString
        supabaseKey = publishableKey
    }

    func restoreBuiltInSupabaseConnection() {
        let bundled = workspaceEnvironment.defaultSupabaseConfig
        supabaseURLString = bundled.url
        supabaseKey = bundled.publishableKey
    }
}
