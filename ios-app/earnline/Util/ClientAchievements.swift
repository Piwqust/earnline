import Foundation

/// Stable identifiers for client achievements. Raw values are persistence-safe
/// even though the first implementation is derived entirely from ledger data.
enum ClientAchievementKind: String, CaseIterable, Identifiable, Sendable {
    case firstPayment = "first_payment"
    case repeatPartner = "repeat_partner"
    case threeProjects = "three_projects"
    case threeMonthRun = "three_month_run"
    case yearTogether = "year_together"
    case coreClient = "core_client"

    var id: String { rawValue }

    /// Material families consumed by the procedural RealityKit medal renderer.
    var material: ClientAchievementMaterial {
        switch self {
        case .firstPayment: .bronze
        case .repeatPartner: .copper
        case .threeProjects: .silver
        case .threeMonthRun: .gold
        case .yearTogether: .roseGold
        case .coreClient: .platinum
        }
    }

    /// Semantic emblems consumed by the medal renderer. These are deliberately
    /// separate from localized titles and from any particular 3D mesh.
    var symbol: ClientAchievementSymbol {
        switch self {
        case .firstPayment: .payment
        case .repeatPartner: .returning
        case .threeProjects: .projects
        case .threeMonthRun: .streak
        case .yearTogether: .anniversary
        case .coreClient: .core
        }
    }
}

enum ClientAchievementMaterial: String, CaseIterable, Sendable {
    case bronze
    case copper
    case silver
    case gold
    case roseGold = "rose_gold"
    case platinum
}

enum ClientAchievementSymbol: String, CaseIterable, Sendable {
    case payment
    case returning
    case projects
    case streak
    case anniversary
    case core

    /// Native fallback glyph for labels, accessibility previews, and rendering
    /// paths that cannot display the procedural RealityKit emblem.
    var sfSymbolName: String {
        switch self {
        case .payment: "banknote.fill"
        case .returning: "arrow.triangle.2.circlepath"
        case .projects: "square.stack.3d.up.fill"
        case .streak: "calendar.badge.checkmark"
        case .anniversary: "calendar.circle.fill"
        case .core: "crown.fill"
        }
    }
}

/// A unit of progress that the UI can format without reverse-engineering a
/// badge's rule. `current` is clamped to `target` once a metric is complete.
struct ClientAchievementMetric: Hashable, Sendable {
    enum Kind: String, Sendable {
        case paidEntries = "paid_entries"
        case distinctProjects = "distinct_projects"
        case consecutiveMonths = "consecutive_months"
        case calendarDays = "calendar_days"
        case activeMonths = "active_months"
    }

    let kind: Kind
    let current: Int
    let target: Int

    init(kind: Kind, current: Int, target: Int) {
        precondition(target > 0)
        self.kind = kind
        self.current = min(max(current, 0), target)
        self.target = target
    }

    var fractionComplete: Double {
        Double(current) / Double(target)
    }
}

struct ClientAchievementProgress: Hashable, Sendable {
    let metrics: [ClientAchievementMetric]

    init(metrics: [ClientAchievementMetric]) {
        precondition(!metrics.isEmpty)
        self.metrics = metrics
    }

    /// Multi-metric badges advance only as far as their least-complete rule.
    var fractionComplete: Double {
        metrics.map(\.fractionComplete).min() ?? 0
    }

    var isComplete: Bool {
        metrics.allSatisfy { $0.current == $0.target }
    }
}

/// One derived badge result in catalog order. `unlockedAt` is the ledger date
/// on which the rule first became true, not a persisted app-observation time.
struct ClientAchievement: Identifiable, Hashable, Sendable {
    let kind: ClientAchievementKind
    let unlockedAt: Date?
    let progress: ClientAchievementProgress

    var id: ClientAchievementKind { kind }
    var isUnlocked: Bool { unlockedAt != nil }
    var material: ClientAchievementMaterial { kind.material }
    var symbol: ClientAchievementSymbol { kind.symbol }
}

/// Incremental input for the achievement catalog. The client snapshot feeds
/// this accumulator from its existing ledger loop, so achievements do not add
/// another fetch or another walk over `EntryRecord` values.
struct ClientAchievementAccumulator: Sendable {
    private let calendar: Calendar
    private var paidDates: [Date] = []
    private var projectFirstDates: [String: Date] = [:]
    private var monthFirstDates: [Int: Date] = [:]

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    mutating func record(date: Date, project: String?, statusRaw: String) {
        guard EntryStatus.fromSyncRawValue(statusRaw) == .paid else { return }

        paidDates.append(date)
        let month = monthKey(date)
        monthFirstDates[month] = earliest(monthFirstDates[month], date)

        guard let project = normalizedProject(project) else { return }
        projectFirstDates[project] = earliest(projectFirstDates[project], date)
    }

    func achievements() -> [ClientAchievement] {
        let dates = paidDates.sorted()
        let paidCount = dates.count
        let projectDates = projectFirstDates.values.sorted()
        let months = monthFirstDates.keys.sorted()
        let streak = streakFacts(months)
        let anniversary = anniversaryFacts(dates)

        let coreUnlockedAt: Date? = if dates.count >= 25, months.count >= 6,
                                              let sixthMonthDate = monthFirstDates[months[5]] {
            max(dates[24], sixthMonthDate)
        } else {
            nil
        }

        return [
            achievement(
                .firstPayment,
                unlockedAt: dates.first,
                metrics: [metric(.paidEntries, paidCount, 1)]
            ),
            achievement(
                .repeatPartner,
                unlockedAt: dates.count >= 5 ? dates[4] : nil,
                metrics: [metric(.paidEntries, paidCount, 5)]
            ),
            achievement(
                .threeProjects,
                unlockedAt: projectDates.count >= 3 ? projectDates[2] : nil,
                metrics: [metric(.distinctProjects, projectDates.count, 3)]
            ),
            achievement(
                .threeMonthRun,
                unlockedAt: streak.unlockedAt,
                metrics: [metric(.consecutiveMonths, streak.longestRun, 3)]
            ),
            achievement(
                .yearTogether,
                unlockedAt: anniversary.unlockedAt,
                metrics: [metric(.calendarDays, anniversary.elapsedDays, anniversary.targetDays)]
            ),
            achievement(
                .coreClient,
                unlockedAt: coreUnlockedAt,
                metrics: [
                    metric(.paidEntries, paidCount, 25),
                    metric(.activeMonths, months.count, 6),
                ]
            ),
        ]
    }

    private func achievement(
        _ kind: ClientAchievementKind,
        unlockedAt: Date?,
        metrics: [ClientAchievementMetric]
    ) -> ClientAchievement {
        ClientAchievement(
            kind: kind,
            unlockedAt: unlockedAt,
            progress: ClientAchievementProgress(metrics: metrics)
        )
    }

    private func metric(
        _ kind: ClientAchievementMetric.Kind,
        _ current: Int,
        _ target: Int
    ) -> ClientAchievementMetric {
        ClientAchievementMetric(kind: kind, current: current, target: target)
    }

    private func streakFacts(_ months: [Int]) -> (longestRun: Int, unlockedAt: Date?) {
        guard let first = months.first else { return (0, nil) }

        var previous = first
        var currentRun = 1
        var longestRun = 1
        var unlockedAt: Date?

        for month in months.dropFirst() {
            currentRun = month == previous + 1 ? currentRun + 1 : 1
            longestRun = max(longestRun, currentRun)
            if currentRun == 3, unlockedAt == nil {
                unlockedAt = monthFirstDates[month]
            }
            previous = month
        }
        return (longestRun, unlockedAt)
    }

    private func anniversaryFacts(_ dates: [Date]) -> (elapsedDays: Int, targetDays: Int, unlockedAt: Date?) {
        guard let first = dates.first, let last = dates.last else { return (0, 365, nil) }
        let firstDay = calendar.startOfDay(for: first)
        guard let anniversary = calendar.date(byAdding: .year, value: 1, to: firstDay) else {
            return (0, 365, nil)
        }

        let targetDays = max(calendar.dateComponents([.day], from: firstDay, to: anniversary).day ?? 365, 1)
        let lastDay = calendar.startOfDay(for: last)
        let elapsedDays = max(calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0, 0)
        let unlockedAt = dates.first { calendar.startOfDay(for: $0) >= anniversary }
        return (elapsedDays, targetDays, unlockedAt)
    }

    private func normalizedProject(_ project: String?) -> String? {
        guard let project else { return nil }
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func earliest(_ existing: Date?, _ candidate: Date) -> Date {
        guard let existing else { return candidate }
        return min(existing, candidate)
    }

    private func monthKey(_ date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 12 + (components.month ?? 1) - 1
    }
}
