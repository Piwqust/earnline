import SwiftUI
import SwiftData

/// Keeps the editable conversion-rate control independent from the settings
/// sheet's recovery and import state. The parent still owns the draft and the
/// explicit network request.
struct ConversionRateSettingsSection: View {
    let baseCurrencyCode: String
    let secondaryCurrencyCode: String
    let secondaryExample: String
    @Binding var rate: Double
    let isFetchingRate: Bool
    let rateFetchFailed: Bool
    let rateFetchNote: String?
    let onCommitRate: () -> Void
    let onFetchRate: () -> Void

    @FocusState private var rateFieldFocused: Bool

    var body: some View {
        Section {
            HStack {
                SettingsRowLabel(
                    verbatim: "1 \(baseCurrencyCode)",
                    glyph: "chart.line.uptrend.xyaxis"
                )
                Spacer()
                // The decimal pad has no return key, so the draft commits when
                // focus leaves the field or the sheet goes away.
                TextField("Rate", value: $rate, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .focused($rateFieldFocused)
                    .onChange(of: rateFieldFocused) { _, focused in
                        if !focused { onCommitRate() }
                    }
                    .onDisappear(perform: onCommitRate)
                Text(secondaryCurrencyCode)
                    .foregroundStyle(.secondary)
            }
            Button(action: onFetchRate) {
                HStack {
                    SettingsRowLabel(
                        isFetchingRate ? Text("Fetching rate...") : Text("Fetch current rate"),
                        glyph: "arrow.clockwise"
                    )
                    Spacer()
                    if isFetchingRate { ProgressView() }
                }
            }
            .disabled(isFetchingRate)
        } header: {
            Text("Display conversion rate")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let rateFetchNote {
                    Label(
                        rateFetchNote,
                        systemImage: rateFetchFailed
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(rateFetchFailed ? Theme.statusProgress : .secondary)
                }
                Text(
                    "Example: \(CurrencyFormatter.string(100, code: baseCurrencyCode)) = \(secondaryExample). "
                        + "Changing this rate updates converted displays; original entry amounts do not change."
                )
            }
        }
    }
}

/// Sync controls use the app's existing orchestration methods, while the
/// parent sheet retains the destructive cloud-copy confirmation route.
struct SyncSettingsContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context

    let pendingSyncCount: Int
    let isResettingLocalData: Bool
    let onUseCloudCopy: () -> Void

    var body: some View {
        Group {
            LabeledContent("Status") {
                Text(appModel.isSupabaseConfigured ? appModel.syncMessage : String(localized: "Saved on this iPhone"))
            }
            LabeledContent("Pending") {
                Text("\(pendingSyncCount)")
            }
            if let lastSyncAt = appModel.lastSyncAt {
                LabeledContent("Last sync") {
                    Text(DateFormat.dotted(lastSyncAt))
                }
            }
            Button {
                Task { await appModel.syncNow(context: context) }
            } label: {
                HStack {
                    SettingsRowLabel(
                        appModel.isSyncing ? Text("Syncing...") : Text("Sync now"),
                        glyph: "arrow.triangle.2.circlepath"
                    )
                    Spacer()
                    if appModel.isSyncing { ProgressView() }
                }
            }
            .disabled(appModel.isSyncing || !appModel.isSupabaseConfigured)

            if appModel.syncConflictCount > 0 {
                Button {
                    Task { await appModel.keepLocalConflictChanges(context: context) }
                } label: {
                    SettingsRowLabel("Keep changes from this iPhone", glyph: "iphone")
                }
                .disabled(appModel.isSyncing)

                Button(action: onUseCloudCopy) {
                    SettingsRowLabel("Use cloud copy", glyph: "icloud.and.arrow.down")
                }
                .disabled(appModel.isSyncing || isResettingLocalData)
            }
        }
    }
}

/// Developer-only data actions have no independent state; callbacks keep the
/// parent responsible for destructive confirmations and user-facing errors.
struct DeveloperDataSettingsContent: View {
    let workspaceDisplayName: String
    let isResettingLocalData: Bool
    let isSyncing: Bool
    let onResetAndPull: () -> Void
    let onImportSample: () -> Void
    let onSeedStressData: () -> Void

    var body: some View {
        Button(action: onResetAndPull) {
            HStack {
                SettingsRowLabel("Reset and pull", glyph: "arrow.counterclockwise")
                Spacer()
                if isResettingLocalData {
                    ProgressView()
                } else {
                    Text(workspaceDisplayName)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .disabled(isResettingLocalData || isSyncing)

        Button(action: onImportSample) {
            SettingsRowLabel("Import sample ledger", glyph: "square.and.arrow.down")
        }
        .disabled(isResettingLocalData)

        Button(action: onSeedStressData) {
            SettingsRowLabel("Seed stress dataset", glyph: "speedometer")
        }
        .disabled(isResettingLocalData)
    }
}
