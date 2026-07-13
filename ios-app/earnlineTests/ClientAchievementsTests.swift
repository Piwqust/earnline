import Foundation
import Testing
@testable import earnline

struct ClientAchievementsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func paid(
        _ accumulator: inout ClientAchievementAccumulator,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        project: String? = nil,
        statusRaw: String = EntryStatus.paid.rawValue
    ) {
        accumulator.record(date: date(year, month, day), project: project, statusRaw: statusRaw)
    }

    private func result(
        _ kind: ClientAchievementKind,
        in accumulator: ClientAchievementAccumulator
    ) throws -> ClientAchievement {
        try #require(accumulator.achievements().first { $0.kind == kind })
    }

    @Test func catalogOrderAndRealityKitMetadataAreStable() {
        #expect(ClientAchievementKind.allCases.map(\.rawValue) == [
            "first_payment", "repeat_partner", "three_projects",
            "three_month_run", "year_together", "core_client",
        ])
        #expect(ClientAchievementKind.allCases.map(\.material) == [
            .bronze, .copper, .silver, .gold, .roseGold, .platinum,
        ])
        #expect(ClientAchievementKind.allCases.map(\.symbol) == [
            .payment, .returning, .projects, .streak, .anniversary, .core,
        ])
        #expect(ClientAchievementSymbol.allCases.map(\.sfSymbolName) == [
            "banknote.fill", "arrow.triangle.2.circlepath", "square.stack.3d.up.fill",
            "calendar.badge.checkmark", "calendar.circle.fill", "crown.fill",
        ])
    }

    @Test func onlyPaidAndLegacyLoggedEntriesUnlockBadges() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        paid(&accumulator, 2026, 1, 1, statusRaw: EntryStatus.inProgress.rawValue)
        paid(&accumulator, 2026, 1, 2, statusRaw: EntryStatus.canceled.rawValue)

        #expect(try result(.firstPayment, in: accumulator).isUnlocked == false)

        paid(&accumulator, 2026, 1, 3, statusRaw: "logged")
        let first = try result(.firstPayment, in: accumulator)
        #expect(first.unlockedAt == date(2026, 1, 3))
        #expect(first.progress.metrics == [
            ClientAchievementMetric(kind: .paidEntries, current: 1, target: 1),
        ])
    }

    @Test func repeatPartnerUnlocksOnFifthPaidEntryRegardlessOfInputOrder() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        for day in [5, 1, 4, 2] { paid(&accumulator, 2026, 1, day) }

        let locked = try result(.repeatPartner, in: accumulator)
        #expect(locked.isUnlocked == false)
        #expect(locked.progress.metrics[0].current == 4)

        paid(&accumulator, 2026, 1, 3)
        let unlocked = try result(.repeatPartner, in: accumulator)
        #expect(unlocked.unlockedAt == date(2026, 1, 5))
        #expect(unlocked.progress.isComplete)
    }

    @Test func projectBadgeNormalizesCaseUnicodeAndOuterWhitespace() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        paid(&accumulator, 2026, 1, 1, project: "  CAFÉ  ")
        paid(&accumulator, 2026, 1, 2, project: "cafe\u{301}")
        paid(&accumulator, 2026, 1, 3, project: "   ")
        paid(&accumulator, 2026, 1, 4, project: "Mobile")

        let locked = try result(.threeProjects, in: accumulator)
        #expect(locked.progress.metrics[0].current == 2)
        #expect(locked.isUnlocked == false)

        paid(&accumulator, 2026, 1, 5, project: "Brand")
        #expect(try result(.threeProjects, in: accumulator).unlockedAt == date(2026, 1, 5))
    }

    @Test func monthRunCrossesYearBoundaryAndIgnoresDuplicateMonths() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        paid(&accumulator, 2025, 12, 20)
        paid(&accumulator, 2026, 1, 1)
        paid(&accumulator, 2026, 1, 25)

        let locked = try result(.threeMonthRun, in: accumulator)
        #expect(locked.progress.metrics[0].current == 2)
        #expect(locked.isUnlocked == false)

        paid(&accumulator, 2026, 2, 14)
        #expect(try result(.threeMonthRun, in: accumulator).unlockedAt == date(2026, 2, 14))
    }

    @Test func monthRunProgressUsesLongestRunWhenThereAreGaps() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        paid(&accumulator, 2026, 1, 1)
        paid(&accumulator, 2026, 3, 1)
        paid(&accumulator, 2026, 4, 1)

        let result = try result(.threeMonthRun, in: accumulator)
        #expect(result.progress.metrics[0].current == 2)
        #expect(result.isUnlocked == false)
    }

    @Test func yearTogetherUsesCalendarAnniversaryAndFirstQualifyingLine() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        paid(&accumulator, 2024, 1, 1)
        paid(&accumulator, 2024, 12, 31)

        let locked = try result(.yearTogether, in: accumulator)
        #expect(locked.isUnlocked == false)
        #expect(locked.progress.metrics[0].target == 366)
        #expect(locked.progress.metrics[0].current == 365)

        paid(&accumulator, 2025, 2, 1)
        paid(&accumulator, 2025, 1, 1)
        let unlocked = try result(.yearTogether, in: accumulator)
        #expect(unlocked.unlockedAt == date(2025, 1, 1))
        #expect(unlocked.progress.isComplete)
    }

    @Test func coreClientRequiresBothTwentyFivePaymentsAndSixActiveMonths() throws {
        var accumulator = ClientAchievementAccumulator(calendar: calendar)
        for index in 0..<25 {
            paid(&accumulator, 2026, (index % 5) + 1, (index / 5) + 1)
        }
        let fiveMonths = try result(.coreClient, in: accumulator)
        #expect(fiveMonths.isUnlocked == false)
        #expect(fiveMonths.progress.metrics.map(\.current) == [25, 5])

        paid(&accumulator, 2026, 6, 1)
        let unlocked = try result(.coreClient, in: accumulator)
        #expect(unlocked.unlockedAt == date(2026, 6, 1))
        #expect(unlocked.progress.isComplete)

        var sixMonthsButShort = ClientAchievementAccumulator(calendar: calendar)
        for month in 1...6 { paid(&sixMonthsButShort, 2026, month, 1) }
        #expect(try result(.coreClient, in: sixMonthsButShort).isUnlocked == false)
    }

    @Test func snapshotDerivesOnlyTheSelectedClientsAchievements() throws {
        let targetID = UUID()
        let otherID = UUID()
        let input = ClientDetailSnapshotInput(
            clientID: targetID,
            entries: [
                .init(clientID: otherID, amount: 1, currencyCode: "EUR", project: "Other",
                      date: date(2026, 1, 1), statusRaw: EntryStatus.paid.rawValue),
                .init(clientID: targetID, amount: 1, currencyCode: "EUR", project: "Target",
                      date: date(2026, 1, 2), statusRaw: EntryStatus.paid.rawValue),
            ],
            converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 1)
        )

        let snapshot = input.snapshot(now: date(2026, 1, 3), calendar: calendar)
        #expect(snapshot.achievements.map(\.kind) == ClientAchievementKind.allCases)
        #expect(try #require(snapshot.achievements.first { $0.kind == .firstPayment }).unlockedAt
                == date(2026, 1, 2))
        #expect(try #require(snapshot.achievements.first { $0.kind == .repeatPartner })
            .progress.metrics[0].current == 1)
    }

    @Test func snapshotMergesProjectTotalsUsingTheSharedProjectIdentity() throws {
        let clientID = UUID()
        let input = ClientDetailSnapshotInput(
            clientID: clientID,
            entries: [
                .init(clientID: clientID, amount: 10, currencyCode: "USD", project: " CAFÉ ",
                      date: date(2026, 1, 1), statusRaw: EntryStatus.paid.rawValue),
                .init(clientID: clientID, amount: 20, currencyCode: "USD", project: "cafe\u{301}",
                      date: date(2026, 1, 2), statusRaw: EntryStatus.paid.rawValue),
            ],
            converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 1)
        )

        let projects = input.snapshot(now: date(2026, 1, 3), calendar: calendar).projectTotals
        #expect(projects.count == 1)
        #expect(projects.first?.count == 2)
        #expect(projects.first?.total == 30)
    }
}
