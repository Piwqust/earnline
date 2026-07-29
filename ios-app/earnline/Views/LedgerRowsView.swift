import SwiftUI
import SwiftData

/// Renders the heterogeneous ledger rows and owns their row-level interaction
/// wiring. `LedgerView` keeps screen orchestration and persistence; this view
/// keeps row presentation and native swipe actions together.
struct LedgerRowsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \ProjectIconPreference.projectKey) private var projectIconPreferences: [ProjectIconPreference]

    let rows: [LedgerRow]
    let isSearching: Bool
    let activeComposerClientID: UUID?
    let composerMonth: Date?
    let onOpenClient: (UUID) -> Void
    let onToggleComposer: (Client, Date) -> Void
    let onSetStatus: (Entry, EntryStatus) -> Void
    let onEditEntry: (UUID) -> Void
    let onDeleteEntry: (UUID) -> Void
    let onEditHeading: (UUID) -> Void
    let onDeleteHeading: (UUID) -> Void

    var body: some View {
        ForEach(rows) { row in
            rowView(row)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(insets(for: row))
        }
    }

    @ViewBuilder
    private func rowView(_ row: LedgerRow) -> some View {
        // A sync pull can invalidate a SwiftData model while a recycled List
        // row still exists. Skip that final render; the next query update
        // removes the row from the collection.
        if row.isInvalidated {
            EmptyView()
        } else {
            liveRowView(row)
        }
    }

    @ViewBuilder
    private func liveRowView(_ row: LedgerRow) -> some View {
        switch row {
        case .month(let month, let total):
            MonthDivider(title: DateFormat.month(month), total: total)
                .background(monthAnchorReader(month))
        case .heading(let heading, let month):
            headingRow(heading)
                .background(monthAnchorReader(month))
        case .client(let client, let month, let total):
            ClientChip(
                client: client,
                total: total,
                isComposing: !isSearching && activeComposerClientID == client.id,
                showsAdd: !isSearching,
                onOpen: { onOpenClient(client.id) },
                onAdd: { onToggleComposer(client, month) }
            )
            .background(monthAnchorReader(month))
        case .composer(let client, let month):
            SmartComposer(client: client, month: composerMonth ?? month)
                .transition(.opacity)
                .background(monthAnchorReader(month))
        case .entry(let entry, let month):
            entryRow(entry)
                .background(monthAnchorReader(month))
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        EntryRow(
            entry: entry,
            projectSymbol: projectSymbol(for: entry),
            onSetStatus: { onSetStatus(entry, $0) },
            onEdit: { onEditEntry(entry.id) },
            onDelete: { onDeleteEntry(entry.id) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDeleteEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.statusCanceled)

            Button {
                onEditEntry(entry.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(app.accentColor)
        }
    }

    private func projectSymbol(for entry: Entry) -> ProjectSymbol? {
        guard let project = entry.project, !project.isEmpty else { return nil }
        let key = ProjectIconResolver.normalizedKey(for: project)
        return projectIconPreferences.first { $0.projectKey == key }?.symbol
    }

    private func headingRow(_ heading: Heading) -> some View {
        let title = heading.title.isEmpty ? String(localized: "Untitled") : heading.title
        let date = DateFormat.dotted(heading.date)
        let noteLabel = String(localized: "Note")
        return Button {
            onEditHeading(heading.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Label(noteLabel, systemImage: "note.text")
                        .appFont(11, .medium)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(date)
                        .appFont(11)
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .appFont(15, .medium)
                    .foregroundStyle(Theme.label)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .contextMenu {
            Button(role: .destructive) {
                onDeleteHeading(heading.id)
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(Theme.statusCanceled)
            }
            .tint(Theme.statusCanceled)
        }
        .accessibilityLabel("\(noteLabel): \(title), \(date)")
        .accessibilityHint("Edits note")
    }

    /// List does not currently report changing row identities through
    /// `scrollPosition` on the iOS 27 runtime. Emit the month for the rows
    /// already on screen instead; the ledger chooses the row nearest its top
    /// edge, so both summary cards track the visible month.
    private func monthAnchorReader(_ month: Date) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: MonthAnchorKey.self,
                value: [MonthAnchor(
                    month: month,
                    y: geometry.frame(in: .named("ledger")).minY
                )]
            )
        }
    }

    private func insets(for row: LedgerRow) -> EdgeInsets {
        switch row {
        case .month: EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16)
        case .heading: EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16)
        case .client: EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
        case .composer: EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16)
        case .entry: EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        }
    }
}
