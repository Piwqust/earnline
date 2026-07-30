import Foundation
import Observation
import SwiftData

/// Owns the expensive, derived ledger data that is shared by the visible
/// ledger and its search surface. Presentation routes remain in `LedgerView`;
/// this cache only decides when a fresh SwiftData aggregation is required.
@MainActor
@Observable
final class LedgerSnapshotCache {
    struct SearchStats: Equatable {
        var hitCount = 0
        var earnedTotal: Decimal = .zero
    }

    private static let windowExtensionMonths = 12

    private(set) var ledgerSnapshot: Insights.LedgerSnapshot?
    private(set) var searchSnapshot: Insights.LedgerSnapshot?
    private(set) var searchFilterSource: EntrySearch.FilterSource?
    private(set) var searchStats = SearchStats()

    private var windowMonthCount = 8
    private var isExtendingLedgerWindow = false
    private var isSnapshotRefreshScheduled = false

    var windowStart: Date {
        let thisMonth = DateFormat.monthStart(of: .now)
        return Calendar.current.date(
            byAdding: .month,
            value: -(windowMonthCount - 1),
            to: thisMonth
        ) ?? .distantPast
    }

    /// One scan per query, token, or store change. Holding only these scalar
    /// results avoids retaining SwiftData models that a sync pull can
    /// invalidate while search is open.
    func refreshSearchStats(isSearching: Bool, rowBuilder: LedgerRowBuilder, app: AppModel) {
        guard isSearching else {
            searchStats = SearchStats()
            return
        }
        let hits = rowBuilder.searchHits
        searchStats = SearchStats(
            hitCount: hits.count,
            earnedTotal: hits.reduce(.zero) { total, entry in
                guard entry.status.isIncludedInEarnedTotals else { return total }
                return total + app.toBase(entry.amount, code: entry.currencyCode)
            }
        )
    }

    /// Search deliberately spans every month, while the normal ledger remains
    /// windowed for launch and scrolling performance.
    func beginSearch(app: AppModel, clients: [Client], rowBuilder: LedgerRowBuilder) {
        searchSnapshot = app.insights.ledgerSnapshot(clients)
        searchFilterSource = buildSearchFilterSource(clients: clients)
        refreshSearchStats(isSearching: true, rowBuilder: rowBuilder, app: app)
    }

    func endSearch() {
        searchSnapshot = nil
        searchFilterSource = nil
        searchStats = SearchStats()
    }

    /// Fetch only the current trailing-month window. Whole-ledger facts use
    /// SQL counts; the full object graph is never materialized for the normal
    /// ledger surface.
    func refreshLedgerSnapshot(
        context: ModelContext,
        clients: [Client],
        headings: [Heading],
        app: AppModel,
        isSearching: Bool,
        rowBuilder: LedgerRowBuilder
    ) {
        let start = windowStart
        let inWindow = FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= start })
        let entries = (try? context.fetch(inWindow)) ?? []
        let older = FetchDescriptor<Entry>(predicate: #Predicate { $0.date < start })
        let olderCount = (try? context.fetchCount(older)) ?? 0
        let inProgressRaw = EntryStatus.inProgress.rawValue
        let pending = FetchDescriptor<Entry>(predicate: #Predicate { $0.statusRaw == inProgressRaw })
        let pendingCount = (try? context.fetchCount(pending)) ?? 0
        let visibleHeadingMonths = headings.compactMap { heading -> Date? in
            guard !heading.isInvalidated, heading.date >= start else { return nil }
            return DateFormat.monthStart(of: heading.date)
        }
        let hasOlderHeadings = headings.contains { heading in
            !heading.isInvalidated && heading.date < start
        }
        ledgerSnapshot = app.insights.ledgerSnapshot(
            windowed: entries,
            hasOlderMonths: olderCount > 0 || hasOlderHeadings,
            hasAnyEntries: olderCount > 0 || !entries.isEmpty,
            pendingCount: pendingCount,
            additionalMonths: visibleHeadingMonths
        )
        if isSearching {
            searchSnapshot = app.insights.ledgerSnapshot(clients)
            refreshSearchStats(isSearching: true, rowBuilder: rowBuilder, app: app)
        }
    }

    /// Coalesce a save burst into one later aggregation. A sync pass can save
    /// several times, but only the final state needs to reach the UI.
    func scheduleSnapshotRefresh(
        context: ModelContext,
        clients: [Client],
        headings: [Heading],
        app: AppModel,
        isSearching: Bool,
        rowBuilder: LedgerRowBuilder
    ) {
        guard !isSnapshotRefreshScheduled else { return }
        isSnapshotRefreshScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.isSnapshotRefreshScheduled = false
            guard !Task.isCancelled else { return }
            self.refreshLedgerSnapshot(
                context: context,
                clients: clients,
                headings: headings,
                app: app,
                isSearching: isSearching,
                rowBuilder: rowBuilder
            )
        }
    }

    /// Materialize older months only as the user reaches the current window's
    /// edge. The task is intentionally deferred out of the scroll callback.
    func requestWindowExtension(
        context: ModelContext,
        clients: [Client],
        headings: [Heading],
        app: AppModel,
        isSearching: Bool,
        rowBuilder: LedgerRowBuilder
    ) {
        guard ledgerSnapshot?.hasOlderMonths == true, !isExtendingLedgerWindow else { return }
        isExtendingLedgerWindow = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.isExtendingLedgerWindow = false }
            guard !Task.isCancelled, self.ledgerSnapshot?.hasOlderMonths == true else { return }
            self.windowMonthCount += Self.windowExtensionMonths
            self.refreshLedgerSnapshot(
                context: context,
                clients: clients,
                headings: headings,
                app: app,
                isSearching: isSearching,
                rowBuilder: rowBuilder
            )
        }
    }

    func prefetchWindowIfNeeded(
        for displayedMonth: Date,
        context: ModelContext,
        clients: [Client],
        headings: [Heading],
        app: AppModel,
        isSearching: Bool,
        rowBuilder: LedgerRowBuilder
    ) {
        guard LedgerWindowPrefetch.needsExtension(
            for: displayedMonth,
            windowStart: windowStart,
            hasOlderMonths: ledgerSnapshot?.hasOlderMonths == true
        ) else { return }
        requestWindowExtension(
            context: context,
            clients: clients,
            headings: headings,
            app: app,
            isSearching: isSearching,
            rowBuilder: rowBuilder
        )
    }

    private func buildSearchFilterSource(clients: [Client]) -> EntrySearch.FilterSource {
        var source = EntrySearch.FilterSource()
        source.months = searchSnapshot?.months ?? []
        var seenProjects: Set<String> = []
        var projects: [String] = []
        for client in clients where !client.isInvalidated {
            source.clients.append(.init(id: client.id, name: client.name))
            for entry in client.entries where !entry.isInvalidated {
                guard let project = entry.project,
                      !project.isEmpty,
                      seenProjects.insert(EntrySearch.normalized(project)).inserted
                else { continue }
                projects.append(project)
            }
        }
        source.projects = projects.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return source
    }
}
