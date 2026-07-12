import Foundation
import SwiftData

/// Immutable presentation data for the client profile. The view renders this
/// value instead of repeatedly walking a SwiftData relationship from `body`.
struct ClientDetailSnapshot: Sendable {
    struct MonthPoint: Identifiable, Sendable {
        let month: Date
        let total: Decimal
        var id: Date { month }
    }

    struct StatusTotal: Identifiable, Sendable {
        let statusRaw: String
        let count: Int
        let total: Decimal
        var id: String { statusRaw }
    }

    struct ProjectTotal: Identifiable, Sendable {
        let name: String
        let count: Int
        let total: Decimal
        var id: String { name }
    }

    let total: Decimal
    let averagePerActiveMonth: Decimal
    let shareOfIncome: Double?
    let months: [MonthPoint]
    let statusTotals: [StatusTotal]
    let projectTotals: [ProjectTotal]
    let transactionCount: Int
}

/// Sendable input used by both the background SwiftData loader and unit tests.
/// Aggregation is deliberately one pass over the ledger.
struct ClientDetailSnapshotInput: Sendable {
    struct EntryRecord: Sendable {
        let clientID: UUID?
        let amount: Decimal
        let currencyCode: String
        let project: String?
        let date: Date
        let statusRaw: String
    }

    let clientID: UUID
    let entries: [EntryRecord]
    let converter: CurrencyConverter

    nonisolated func snapshot(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ClientDetailSnapshot {
        var overallEarned = Decimal.zero
        var clientEarned = Decimal.zero
        var monthlyTotals: [Int: Decimal] = [:]
        var statusTotals: [String: (count: Int, total: Decimal)] = [:]
        var projectTotals: [String: (count: Int, total: Decimal)] = [:]
        var transactionCount = 0

        for entry in entries {
            let status = EntryStatus.fromSyncRawValue(entry.statusRaw)
            let base = converter.toBase(entry.amount, code: entry.currencyCode)
            if status.isIncludedInEarnedTotals {
                overallEarned += base
            }
            guard entry.clientID == clientID else { continue }

            transactionCount += 1
            statusTotals[status.rawValue, default: (0, .zero)].count += 1
            statusTotals[status.rawValue, default: (0, .zero)].total += base

            guard status.isIncludedInEarnedTotals else { continue }
            clientEarned += base
            let key = Self.monthKey(entry.date, calendar: calendar)
            monthlyTotals[key, default: .zero] += base
            let project = entry.project?.isEmpty == false ? entry.project! : "—"
            projectTotals[project, default: (0, .zero)].count += 1
            projectTotals[project, default: (0, .zero)].total += base
        }

        let activeMonths = monthlyTotals.values.count { $0 > 0 }
        let thisMonth = Self.monthStart(now, calendar: calendar)
        let months = (0..<12).reversed().compactMap { offset -> ClientDetailSnapshot.MonthPoint? in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return .init(month: month, total: monthlyTotals[Self.monthKey(month, calendar: calendar)] ?? .zero)
        }
        let statuses = EntryStatus.allCases.map { status in
            let value = statusTotals[status.rawValue] ?? (0, .zero)
            return ClientDetailSnapshot.StatusTotal(
                statusRaw: status.rawValue,
                count: value.count,
                total: value.total
            )
        }
        var projects: [ClientDetailSnapshot.ProjectTotal] = []
        projects.reserveCapacity(projectTotals.count)
        for (name, value) in projectTotals {
            projects.append(.init(name: name, count: value.count, total: value.total))
        }
        projects.sort { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return ClientDetailSnapshot(
            total: clientEarned,
            averagePerActiveMonth: activeMonths == 0 ? .zero : clientEarned / Decimal(activeMonths),
            shareOfIncome: overallEarned > 0
                ? NSDecimalNumber(decimal: clientEarned / overallEarned).doubleValue
                : nil,
            months: months,
            statusTotals: statuses,
            projectTotals: projects,
            transactionCount: transactionCount
        )
    }

    private nonisolated static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private nonisolated static func monthKey(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 12 + (components.month ?? 1) - 1
    }
}

/// Fetches and copies SwiftData rows on a private model actor. Opening the
/// profile therefore commits its first frame before any large relationship is
/// faulted or aggregated, and the main actor stays responsive throughout.
@ModelActor
actor ClientDetailSnapshotLoader {
    func load(
        clientID: UUID,
        converter: CurrencyConverter,
        now: Date = .now
    ) throws -> ClientDetailSnapshot {
        let startedAt = ContinuousClock.now
        let descriptor = FetchDescriptor<Entry>()
        let records = try modelContext.fetch(descriptor).compactMap { entry -> ClientDetailSnapshotInput.EntryRecord? in
            guard !entry.isDeleted else { return nil }
            return .init(
                clientID: entry.client?.id,
                amount: entry.amount,
                currencyCode: entry.currencyCode,
                project: entry.project,
                date: entry.date,
                statusRaw: entry.statusRaw
            )
        }
        let snapshot = ClientDetailSnapshotInput(clientID: clientID, entries: records, converter: converter)
            .snapshot(now: now)
        #if DEBUG
        let elapsed = startedAt.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1_000
            + Double(elapsed.attoseconds) / 1_000_000_000_000_000
        let durationText = String(format: "%.1f", milliseconds)
        print("⏱️ client profile snapshot: \(records.count) entries in \(durationText) ms")
        #endif
        return snapshot
    }
}
