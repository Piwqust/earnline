import SwiftUI
import SwiftData

/// Renders the heterogeneous ledger rows and owns their row-level interaction
/// wiring. `LedgerView` keeps screen orchestration and persistence; this view
/// keeps row presentation and native swipe actions together.
struct LedgerRowsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \ProjectIconPreference.projectKey) private var projectIconPreferences: [ProjectIconPreference]
    @State private var monthMarkerOffsets: [LedgerScrollTarget: CGFloat] = [:]
    @State private var monthTrackingTopY: CGFloat?
    @State private var monthTrackingAnchorID: LedgerScrollTarget?
    @State private var activeMonthMarkerID: LedgerScrollTarget?
    @State private var lastReportedVisibleMonth: Date?

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
    let onTopVisibleMonthChange: (Date?) -> Void

    var body: some View {
        ForEach(rows) { row in
            let rowID = row.id
            let isMonth = row.isMonthMarker
            rowView(row)
                .onGeometryChange(for: CGFloat?.self) { proxy in
                    guard isMonth else { return nil }
                    return proxy.frame(in: .named("ledger.scroll")).minY
                } action: { minY in
                    guard let minY else { return }
                    updateMonthPosition(for: rowID, minY: minY)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(insets(for: row))
        }
        .onChange(of: rows.map(\.id)) { _, rowIDs in
            monthMarkerOffsets = monthMarkerOffsets.filter { rowIDs.contains($0.key) }
            let newestMarkerID = newestMonthMarkerID
            if monthTrackingAnchorID != newestMarkerID {
                monthTrackingAnchorID = newestMarkerID
                monthTrackingTopY = nil
                activeMonthMarkerID = newestMarkerID
            }
            reportTopVisibleMonth()
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
        case .heading(let heading, _):
            headingRow(heading)
        case .client(let client, let month, let total):
            ClientChip(
                client: client,
                total: total,
                isComposing: !isSearching && activeComposerClientID == client.id,
                showsAdd: !isSearching,
                onOpen: { onOpenClient(client.id) },
                onAdd: { onToggleComposer(client, month) }
            )
        case .composer(let client, let month):
            // The actual composer uses its explicit route month when present;
            // the row identifier continues to carry the represented month for
            // the surrounding scroll target layout.
            SmartComposer(client: client, month: composerMonth ?? month)
                .transition(.opacity)
        case .entry(let entry, _):
            entryRow(entry)
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

    private func updateMonthPosition(for rowID: LedgerScrollTarget, minY: CGFloat) {
        // `onScrollVisibilityChange` leaves stale visible rows behind in an
        // iOS 26 `List`. Month dividers are sparse, so tracking only their
        // actual row positions is both deterministic and cheap.
        if rowID == newestMonthMarkerID {
            monthTrackingAnchorID = rowID
            // The first month divider reveals the actual content boundary
            // below the safe-area summary. That boundary differs between iOS
            // 26 and 27, so retain its highest observed resting position
            // instead of assuming zero.
            monthTrackingTopY = max(monthTrackingTopY ?? minY, minY)
            if activeMonthMarkerID == nil {
                activeMonthMarkerID = rowID
            }
        }
        let previousY = monthMarkerOffsets[rowID]
        monthMarkerOffsets[rowID] = minY
        guard let monthTrackingTopY, let previousY else {
            reportTopVisibleMonth()
            return
        }

        if previousY > monthTrackingTopY, minY <= monthTrackingTopY {
            // Scrolling toward older entries: the divider that just reached
            // the header becomes the active month.
            activeMonthMarkerID = rowID
        } else if previousY <= monthTrackingTopY,
                  minY > monthTrackingTopY,
                  activeMonthMarkerID == rowID {
            // Scrolling back toward newer entries: hand ownership to the
            // immediately newer divider in ledger order.
            activeMonthMarkerID = newerMonthMarkerID(than: rowID)
        }
        reportTopVisibleMonth()
    }

    private func reportTopVisibleMonth() {
        guard let activeMarker = activeMonthMarkerID ?? newestMonthMarkerID else { return }
        let month = DateFormat.monthStart(of: activeMarker.representedMonth)
        guard lastReportedVisibleMonth.map({
            !Calendar.current.isDate($0, equalTo: month, toGranularity: .month)
        }) ?? true else { return }
        lastReportedVisibleMonth = month
        guard !isSearching else { return }
        onTopVisibleMonthChange(month)
    }

    private var newestMonthMarkerID: LedgerScrollTarget? {
        rows.lazy.compactMap { row in
            if case .month = row { return row.id }
            return nil
        }.first
    }

    private func newerMonthMarkerID(than markerID: LedgerScrollTarget) -> LedgerScrollTarget? {
        let markerIDs = rows.compactMap { row in
            row.isMonthMarker ? row.id : nil
        }
        guard let index = markerIDs.firstIndex(of: markerID), index > markerIDs.startIndex else {
            return markerIDs.first
        }
        return markerIDs[markerIDs.index(before: index)]
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDeleteHeading(heading.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.statusCanceled)
        }
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
