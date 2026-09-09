import SwiftUI
import SwiftData

/// The automatic copies Earnline wrote before emptying this local store.
/// Restoring is the same merge-only import as a manual backup: nothing already
/// in the ledger is touched, and restored rows sync as new local changes.
struct SafetySnapshotsView: View {
    @Environment(AppModel.self) private var app

    @State private var snapshots: [LedgerSafetySnapshots.Snapshot] = []
    @State private var loadError: String?
    @State private var pendingDelete: LedgerSafetySnapshots.Snapshot?

    var body: some View {
        List {
            if snapshots.isEmpty {
                ContentUnavailableView {
                    Label("No safety snapshots yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    // swiftlint:disable:next line_length
                    Text("Earnline writes one automatically before “Use cloud copy” or “Reset and pull” empties the local ledger on this iPhone.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(snapshots) { snapshot in
                        NavigationLink {
                            SafetySnapshotDetailView(snapshot: snapshot, onChange: reload)
                        } label: {
                            SafetySnapshotRow(snapshot: snapshot)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = snapshot
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    // swiftlint:disable:next line_length
                    Text("The newest \(LedgerSafetySnapshots.retainedCount) snapshots of this store are kept. Restoring adds missing records and never overwrites rows already in the ledger.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Safety snapshots")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .task(id: app.workspaceStoreIdentity) { reload() }
        .saveErrorAlert($loadError, title: "Could not read safety snapshots")
        .confirmationDialog(
            "Delete this snapshot?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { snapshot in
            Button("Delete snapshot", role: .destructive) { delete(snapshot) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { snapshot in
            Text(snapshot.title)
        }
        .accessibilityIdentifier("settings.safetySnapshots")
    }

    private func reload() {
        do {
            snapshots = try LedgerSafetySnapshots.list(forStoreIdentity: app.workspaceStoreIdentity)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ snapshot: LedgerSafetySnapshots.Snapshot) {
        do {
            try LedgerSafetySnapshots.delete(snapshot)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
        pendingDelete = nil
    }
}

private struct SafetySnapshotRow: View {
    let snapshot: LedgerSafetySnapshots.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.title)
                .foregroundStyle(Theme.label)
            HStack(spacing: 6) {
                Text(snapshot.createdAt, format: .dateTime.day().month().year().hour().minute())
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: Int64(snapshot.fileSize), countStyle: .file))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One snapshot: what it holds, what restoring would add, and the restore
/// itself behind an explicit confirmation.
struct SafetySnapshotDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let snapshot: LedgerSafetySnapshots.Snapshot
    let onChange: () -> Void

    @State private var backup: LedgerBackup?
    @State private var plan: LedgerBackup.ImportSummary?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var confirmsRestore = false
    @State private var restoredSummary: LedgerBackup.ImportSummary?

    var body: some View {
        Form {
            Section("Snapshot") {
                LabeledContent("Taken") {
                    Text(snapshot.createdAt, format: .dateTime.day().month().year().hour().minute())
                }
                LabeledContent("Reason", value: snapshot.title)
                if let backup {
                    LabeledContent("Workspace in file", value: backup.workspaceID)
                    LabeledContent("Currencies in file",
                                   value: "\(backup.settings.baseCurrencyCode) / \(backup.settings.secondaryCurrencyCode)")
                    LabeledContent("Records", value: "\(backup.totalRecords)")
                    LabeledContent("Clients", value: "\(backup.clients.count)")
                    LabeledContent("Income lines", value: "\(backup.entries.count)")
                    LabeledContent("Notes", value: "\(backup.headings.count)")
                    LabeledContent("Project icons", value: "\(backup.projectIcons.count)")
                    LabeledContent("Month reviews", value: "\(backup.monthReviews.count)")
                }
            }

            if let plan {
                Section {
                    LabeledContent("New records", value: "\(plan.inserted)")
                    LabeledContent("Already in the ledger", value: "\(plan.skippedExisting)")
                    Button("Restore \(plan.inserted) records") {
                        confirmsRestore = true
                    }
                    .disabled(plan.inserted == 0)
                    .accessibilityIdentifier("settings.safetySnapshots.restore")
                } header: {
                    Text("Restore")
                } footer: {
                    // swiftlint:disable:next line_length
                    Text("Only records missing from the current ledger are added. Currency settings in the snapshot are shown for reference and are not applied.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Safety snapshot")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: mutations.dataRevision) { load() }
        .confirmationDialog(
            "Restore this snapshot?",
            isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button("Restore") { restore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing rows stay unchanged. Missing rows are added as local changes and can sync to this workspace.")
        }
        .alert(
            "Snapshot restored",
            isPresented: Binding(
                get: { restoredSummary != nil },
                set: { if !$0 { restoredSummary = nil } }
            )
        ) {
            Button("Done") {
                onChange()
                dismiss()
            }
        } message: {
            if let restoredSummary {
                Text("Added \(restoredSummary.inserted) records. Skipped \(restoredSummary.skippedExisting) already present.")
            }
        }
        .saveErrorAlert($loadError, title: "Could not read this snapshot")
        .saveErrorAlert($saveError, title: "Could not restore this snapshot")
    }

    private func load() {
        do {
            let loaded = try LedgerSafetySnapshots.load(snapshot)
            backup = loaded
            plan = try LedgerBackupCodec.importPlan(loaded, into: context)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func restore() {
        guard let backup else { return }
        do {
            let summary = try LedgerBackupCodec.importBackup(backup, into: context)
            guard summary.inserted > 0 else {
                restoredSummary = summary
                return
            }
            if let error = mutations.save(context) {
                saveError = error
            } else {
                restoredSummary = summary
            }
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}
