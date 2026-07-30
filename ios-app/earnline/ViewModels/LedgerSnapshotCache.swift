import Foundation
import Observation
import SwiftData

/// Owns the expensive, derived ledger data that is shared by the visible
/// ledger and its search surface. Presentation routes remain in `LedgerView`;
/// this cache only decides when a fresh SwiftData aggregation is required.
@MainActor
@Observable
final class LedgerSnapshotCache {
    /// Everything an aggregation pass reads, gathered once per body evaluation
    /// by `LedgerView`. Passing one value keeps the six inputs from being
    /// restated at every call site — and, more importantly, guarantees a
    /// deferred pass sees the same set the caller resolved, rather than six
    /// arguments threaded independently through four methods.
    struct Inputs {
        let context: ModelContext
        let clients: [Client]
        let headings: [Heading]
        let app: AppModel
        let isSearching: Bool
        let rowBuilder: LedgerRowBuilder
    }

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
    /// Held rather than fire-and-forgotten. `LedgerView` is `.id`-keyed on the
    /// workspace store, so a switch releases this cache while a deferred pass
    /// may still be queued against the outgoing `ModelContext`; `deinit` cancels
    /// it. The handles double as the coalescing flags, and they are what makes
    /// the `Task.isCancelled` checks inside the tasks meaningful — an
    /// unstructured task nobody holds is never cancelled, so guarding on it
    /// would read as protection that isn't there.
    @ObservationIgnored private var snapshotRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var windowExtensionTask: Task<Void, Never>?

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
    func refreshSearchStats(_ inputs: Inputs) {
        searchStats = inputs.isSearching ? scanSearchHits(inputs) : SearchStats()
    }

    /// Search deliberately spans every month, while the normal ledger remains
    /// windowed for launch and scrolling performance.
    ///
    /// The scan is unconditional here: this *is* the transition into search, so
    /// it must not depend on the caller's `isSearching` already agreeing.
    func beginSearch(_ inputs: Inputs) {
        searchSnapshot = inputs.app.insights.ledgerSnapshot(inputs.clients)
        searchFilterSource = buildSearchFilterSource(clients: inputs.clients)
        searchStats = scanSearchHits(inputs)
    }

    private func scanSearchHits(_ inputs: Inputs) -> SearchStats {
        let hits = inputs.rowBuilder.searchHits
        return SearchStats(
            hitCount: hits.count,
            earnedTotal: hits.reduce(.zero) { total, entry in
                guard entry.status.isIncludedInEarnedTotals else { return total }
                return total + inputs.app.toBase(entry.amount, code: entry.currencyCode)
            }
        )
    }

    func endSearch() {
        searchSnapshot = nil
        searchFilterSource = nil
        searchStats = SearchStats()
    }

    /// Fetch only the current trailing-month window. Whole-ledger facts use
    /// SQL counts; the full object graph is never materialized for the normal
    /// ledger surface.
    func refreshLedgerSnapshot(_ inputs: Inputs) {
        let context = inputs.context
        let start = windowStart
        let inWindow = FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= start })
        let entries = (try? context.fetch(inWindow)) ?? []
        let older = FetchDescriptor<Entry>(predicate: #Predicate { $0.date < start })
        let olderCount = (try? context.fetchCount(older)) ?? 0
        let inProgressRaw = EntryStatus.inProgress.rawValue
        let pending = FetchDescriptor<Entry>(predicate: #Predicate { $0.statusRaw == inProgressRaw })
        let pendingCount = (try? context.fetchCount(pending)) ?? 0
        let visibleHeadingMonths = inputs.headings.compactMap { heading -> Date? in
            guard !heading.isInvalidated, heading.date >= start else { return nil }
            return DateFormat.monthStart(of: heading.date)
        }
        let hasOlderHeadings = inputs.headings.contains { heading in
            !heading.isInvalidated && heading.date < start
        }
        ledgerSnapshot = inputs.app.insights.ledgerSnapshot(
            windowed: entries,
            hasOlderMonths: olderCount > 0 || hasOlderHeadings,
            hasAnyEntries: olderCount > 0 || !entries.isEmpty,
            pendingCount: pendingCount,
            additionalMonths: visibleHeadingMonths
        )
        if inputs.isSearching {
            searchSnapshot = inputs.app.insights.ledgerSnapshot(inputs.clients)
            searchStats = scanSearchHits(inputs)
        }
    }

    /// Coalesce a save burst into one later aggregation. A sync pass can save
    /// several times, but only the final state needs to reach the UI.
    func scheduleSnapshotRefresh(_ inputs: Inputs) {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.snapshotRefreshTask = nil
            guard !Task.isCancelled else { return }
            self.refreshLedgerSnapshot(inputs)
        }
    }

    /// Materialize older months only as the user reaches the current window's
    /// edge. The task is intentionally deferred out of the scroll callback.
    func requestWindowExtension(_ inputs: Inputs) {
        guard ledgerSnapshot?.hasOlderMonths == true, windowExtensionTask == nil else { return }
        windowExtensionTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.windowExtensionTask = nil }
            guard !Task.isCancelled, self.ledgerSnapshot?.hasOlderMonths == true else { return }
            self.windowMonthCount += Self.windowExtensionMonths
            self.refreshLedgerSnapshot(inputs)
        }
    }

    func prefetchWindowIfNeeded(for displayedMonth: Date, inputs: Inputs) {
        guard LedgerWindowPrefetch.needsExtension(
            for: displayedMonth,
            windowStart: windowStart,
            hasOlderMonths: ledgerSnapshot?.hasOlderMonths == true
        ) else { return }
        requestWindowExtension(inputs)
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

    deinit {
        snapshotRefreshTask?.cancel()
        windowExtensionTask?.cancel()
    }
}
