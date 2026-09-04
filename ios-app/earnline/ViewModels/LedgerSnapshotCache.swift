import Foundation
import Observation
import OSLog
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
    private(set) var searchHitIDs: Set<UUID> = []
    private(set) var loadError: String?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.earnline.app",
        category: "ledger-data"
    )

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
        guard inputs.isSearching else {
            searchHitIDs = []
            searchStats = SearchStats()
            return
        }
        do {
            applySearchScan(try scanSearchHits(inputs))
        } catch {
            Self.logger.error("Could not scan search hits: \(error.localizedDescription, privacy: .public)")
            loadError = String(localized: "Could not search your ledger. Your last saved view is still shown. Try again.")
        }
    }

    /// Search deliberately spans every month, while the normal ledger remains
    /// windowed for launch and scrolling performance.
    ///
    /// The scan is unconditional here: this *is* the transition into search, so
    /// it must not depend on the caller's `isSearching` already agreeing.
    func beginSearch(_ inputs: Inputs) {
        do {
            let entries = try inputs.context.fetch(FetchDescriptor<Entry>())
            searchSnapshot = fullLedgerSnapshot(entries: entries, inputs: inputs)
            searchFilterSource = buildSearchFilterSource(clients: inputs.clients, entries: entries)
            applySearchScan(scanSearchHits(entries: entries, inputs: inputs))
            loadError = nil
        } catch {
            Self.logger.error("Could not open search: \(error.localizedDescription, privacy: .public)")
            loadError = String(localized: "Could not search your ledger. Your last saved view is still shown. Try again.")
        }
    }

    private struct SearchScan {
        let stats: SearchStats
        let ids: Set<UUID>
    }

    private func applySearchScan(_ scan: SearchScan) {
        searchHitIDs = scan.ids
        searchStats = scan.stats
    }

    private func scanSearchHits(_ inputs: Inputs) throws -> SearchScan {
        scanSearchHits(entries: try inputs.context.fetch(FetchDescriptor<Entry>()), inputs: inputs)
    }

    private func scanSearchHits(entries: [Entry], inputs: Inputs) -> SearchScan {
        let startedAt = ContinuousClock.now
        let filter = EntrySearch.Filter(query: inputs.rowBuilder.searchQuery, tokens: inputs.rowBuilder.searchTokens)
        let hits: [Entry]
        if filter.isActive {
            hits = entries.filter { entry in
                guard !entry.isInvalidated, let client = entry.client, !client.isInvalidated else { return false }
                return filter.matches(entry, clientID: client.id, clientName: client.name)
            }
        } else {
            hits = []
        }
        let stats = SearchStats(
            hitCount: hits.count,
            earnedTotal: hits.reduce(.zero) { total, entry in
                guard entry.status.isIncludedInEarnedTotals else { return total }
                return total + inputs.app.toBase(entry.amount, code: entry.currencyCode)
            }
        )
        let elapsed = startedAt.duration(to: .now)
        Self.logger.debug("Search scanned \(hits.count) matching entries in \(elapsed, privacy: .public)")
        return SearchScan(stats: stats, ids: Set(hits.map(\.id)))
    }

    func endSearch() {
        searchSnapshot = nil
        searchFilterSource = nil
        searchHitIDs = []
        searchStats = SearchStats()
    }

    /// Fetch only the current trailing-month window. Whole-ledger facts use
    /// SQL counts; the full object graph is never materialized for the normal
    /// ledger surface.
    func refreshLedgerSnapshot(_ inputs: Inputs) {
        let context = inputs.context
        let start = windowStart
        let inWindow = FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= start })
        let older = FetchDescriptor<Entry>(predicate: #Predicate { $0.date < start })
        let inProgressRaw = EntryStatus.inProgress.rawValue
        let pending = FetchDescriptor<Entry>(predicate: #Predicate { $0.statusRaw == inProgressRaw })
        do {
            let entries = try context.fetch(inWindow)
            let olderCount = try context.fetchCount(older)
            let pendingCount = try context.fetchCount(pending)
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
                let allEntries = try context.fetch(FetchDescriptor<Entry>())
                searchSnapshot = fullLedgerSnapshot(entries: allEntries, inputs: inputs)
                searchFilterSource = buildSearchFilterSource(clients: inputs.clients, entries: allEntries)
                applySearchScan(scanSearchHits(entries: allEntries, inputs: inputs))
            }
            loadError = nil
        } catch {
            Self.logger.error("Could not refresh ledger snapshot: \(error.localizedDescription, privacy: .public)")
            // Preserve the last known-good snapshot. Showing an empty ledger
            // after a read failure is indistinguishable from data loss.
            loadError = String(localized: "Could not load your ledger. Your last saved view is still shown. Try again.")
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

    /// Search needs every month, but it should still be one table fetch rather
    /// than walking `client.entries` and faulting the whole graph twice.
    private func fullLedgerSnapshot(entries: [Entry], inputs: Inputs) -> Insights.LedgerSnapshot {
        let pendingCount = entries.reduce(into: 0) { count, entry in
            if !entry.isDeleted && entry.status == .inProgress { count += 1 }
        }
        let extraMonths = inputs.headings.compactMap { heading -> Date? in
            guard !heading.isInvalidated else { return nil }
            return DateFormat.monthStart(of: heading.date)
        }
        return inputs.app.insights.ledgerSnapshot(
            windowed: entries,
            hasOlderMonths: false,
            hasAnyEntries: !entries.isEmpty,
            pendingCount: pendingCount,
            additionalMonths: extraMonths
        )
    }

    private func buildSearchFilterSource(clients: [Client], entries: [Entry]) -> EntrySearch.FilterSource {
        var source = EntrySearch.FilterSource()
        source.months = searchSnapshot?.months ?? []
        var seenProjects: Set<String> = []
        var projects: [String] = []
        for client in clients where !client.isInvalidated {
            source.clients.append(.init(id: client.id, name: client.name))
        }
        for entry in entries where !entry.isInvalidated {
            guard let project = entry.project,
                  !project.isEmpty,
                  seenProjects.insert(EntrySearch.normalized(project)).inserted
            else { continue }
            projects.append(project)
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
