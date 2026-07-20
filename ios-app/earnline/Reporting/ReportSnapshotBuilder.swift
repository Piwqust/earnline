import Foundation

/// Builds an immutable report from already-copied ledger values. All monetary
/// aggregation happens here, never in a SwiftUI `body` or an image renderer.
struct ReportSnapshotBuilder: Sendable {
    private let input: ReportSnapshotInput

    init(input: ReportSnapshotInput) {
        self.input = input
    }

    func snapshot(
        scope: ReportScope,
        audience: ReportAudience,
        generatedAt: Date = .now,
        calendar: Calendar = .current
    ) -> ReportSnapshot {
        let period = scope.period(calendar: calendar)
        let reportEntries = entries(in: period, audience: audience)
        let summary = summarize(reportEntries)
        let notes = notes(in: period, audience: audience)

        let lastYearComparison: ReportLastYearComparison?
        if audience == .personal, scope.isMonth {
            let previousPeriod = scope.oneYearEarlier(calendar: calendar).period(calendar: calendar)
            let previous = summarize(self.entries(in: previousPeriod, audience: audience))
            lastYearComparison = (summary.includedEntryCount > 0 || previous.includedEntryCount > 0)
                ? comparison(current: summary, previous: previous, period: previousPeriod)
                : nil
        } else {
            lastYearComparison = nil
        }

        return ReportSnapshot(
            scope: scope,
            audience: audience,
            period: period,
            generatedAt: generatedAt,
            entries: reportEntries,
            eventNotes: notes,
            clientCount: Set(reportEntries.map(\.clientID)).count,
            includedEntryCount: summary.includedEntryCount,
            canceledEntryCount: summary.canceledEntryCount,
            originalCurrencyTotals: summary.currencyTotals,
            paid: summary.paid,
            inProgress: summary.inProgress,
            usdEquivalent: summary.usdEquivalent,
            lastYearComparison: lastYearComparison,
            monthReview: review(in: period, scope: scope, audience: audience)
        )
    }

    private func entries(in period: ReportPeriod, audience: ReportAudience) -> [ReportEntry] {
        input.entries
            .filter { entry in
                period.contains(entry.date)
                    && (audience.clientID == nil || audience.clientID == entry.clientID)
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                if lhs.clientName != rhs.clientName {
                    return lhs.clientName.localizedStandardCompare(rhs.clientName) == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func notes(in period: ReportPeriod, audience: ReportAudience) -> [ReportEventNote] {
        guard audience == .personal else { return [] }
        return input.eventNotes
            .filter { period.contains($0.date) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func review(
        in period: ReportPeriod,
        scope: ReportScope,
        audience: ReportAudience
    ) -> ReportMonthReview? {
        guard audience == .personal, scope.isMonth else { return nil }
        return input.monthReviews
            .filter { period.contains($0.monthStart) }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
            .first
    }

    private func summarize(_ entries: [ReportEntry]) -> ReportSummary {
        let paidEntries = entries.filter { $0.status == .paid }
        let inProgressEntries = entries.filter { $0.status == .inProgress }
        let includedEntries = paidEntries + inProgressEntries

        return ReportSummary(
            includedEntryCount: includedEntries.count,
            canceledEntryCount: entries.count { $0.status == .canceled },
            currencyTotals: currencyTotals(for: includedEntries),
            paid: statusTotal(for: .paid, entries: paidEntries),
            inProgress: statusTotal(for: .inProgress, entries: inProgressEntries),
            usdEquivalent: usdEquivalent(for: includedEntries)
        )
    }

    private func statusTotal(
        for status: ReportEntryStatus,
        entries: [ReportEntry]
    ) -> ReportStatusTotal {
        ReportStatusTotal(
            status: status,
            entryCount: entries.count,
            currencyTotals: currencyTotals(for: entries),
            usdEquivalent: usdEquivalent(for: entries)
        )
    }

    private func currencyTotals(for entries: [ReportEntry]) -> [ReportCurrencyTotal] {
        var buckets: [String: (amount: Decimal, count: Int)] = [:]
        for entry in entries {
            let code = entry.currencyCode.uppercased()
            buckets[code, default: (.zero, 0)].amount += entry.amount
            buckets[code, default: (.zero, 0)].count += 1
        }
        return buckets.map { code, value in
            ReportCurrencyTotal(currencyCode: code, amount: value.amount, entryCount: value.count)
        }
        .sorted { lhs, rhs in
            lhs.currencyCode.localizedStandardCompare(rhs.currencyCode) == .orderedAscending
        }
    }

    private func usdEquivalent(for entries: [ReportEntry]) -> ReportUSDEquivalent? {
        let baseCode = input.converter.baseCurrencyCode.uppercased()
        let secondaryCode = input.converter.secondaryCurrencyCode.uppercased()
        guard baseCode == "USD" || secondaryCode == "USD" else { return nil }

        var total = Decimal.zero
        var convertedEntryCount = 0
        var excluded: [String: (amount: Decimal, count: Int)] = [:]

        for entry in entries {
            let code = entry.currencyCode.uppercased()
            guard input.converter.canConvert(code) else {
                excluded[code, default: (.zero, 0)].amount += entry.amount
                excluded[code, default: (.zero, 0)].count += 1
                continue
            }

            let baseAmount = input.converter.toBase(entry.amount, code: code)
            total += baseCode == "USD" ? baseAmount : input.converter.secondary(baseAmount)
            convertedEntryCount += 1
        }

        let excludedTotals = excluded.map { code, value in
            ReportCurrencyTotal(currencyCode: code, amount: value.amount, entryCount: value.count)
        }
        .sorted { lhs, rhs in
            lhs.currencyCode.localizedStandardCompare(rhs.currencyCode) == .orderedAscending
        }

        return ReportUSDEquivalent(
            amount: total,
            convertedEntryCount: convertedEntryCount,
            excludedCurrencyTotals: excludedTotals,
            baseCurrencyCode: baseCode,
            secondaryCurrencyCode: secondaryCode,
            secondaryUnitsPerBase: input.converter.secondary(1)
        )
    }

    private func comparison(
        current: ReportSummary,
        previous: ReportSummary,
        period: ReportPeriod
    ) -> ReportLastYearComparison {
        let currentByCode = Dictionary(uniqueKeysWithValues: current.currencyTotals.map { ($0.currencyCode, $0) })
        let previousByCode = Dictionary(uniqueKeysWithValues: previous.currencyTotals.map { ($0.currencyCode, $0) })
        let codes = Set(currentByCode.keys).union(previousByCode.keys)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let currencyChanges = codes.map { code in
            ReportCurrencyChange(
                currencyCode: code,
                current: currentByCode[code]?.amount ?? .zero,
                previous: previousByCode[code]?.amount ?? .zero
            )
        }
        let usdEquivalent: ReportUSDChange? = switch (current.usdEquivalent, previous.usdEquivalent) {
        case let (current?, previous?): ReportUSDChange(current: current.amount, previous: previous.amount)
        default: nil
        }

        return ReportLastYearComparison(
            period: period,
            entryCount: previous.includedEntryCount,
            currencyChanges: currencyChanges,
            usdEquivalent: usdEquivalent
        )
    }
}

private struct ReportSummary: Sendable {
    let includedEntryCount: Int
    let canceledEntryCount: Int
    let currencyTotals: [ReportCurrencyTotal]
    let paid: ReportStatusTotal
    let inProgress: ReportStatusTotal
    let usdEquivalent: ReportUSDEquivalent?
}
