import AppIntents
import Foundation
import SwiftData
import Testing
import UIKit
import UserNotifications
@testable import earnline

@MainActor
@Suite(.serialized)
struct SystemIntegrationTests {
    @Test func shortcutsUseTheVisibleStoreAndRejectAnotherWorkspace() async throws {
        let defaults = try #require(UserDefaults(suiteName: "integration-\(UUID())"))
        let app = AppModel(defaults: defaults)
        app.continueWithoutAccount()
        app.workspaceID = "integration-\(UUID())"
        app.workspaceStoreIdentity = app.workspaceID
        let originalApp = EarnlineRuntime.shared.app
        EarnlineRuntime.shared.app = app
        defer { EarnlineRuntime.shared.app = originalApp }
        let (_, context) = try EarnlineRuntime.shared.ledger()
        let client = Client(name: "Fixture")
        context.insert(client)
        try context.save()
        let entity = try #require(IntentLedgerStore.clients().first)
        let before = app.mutations.dataRevision
        try await IntentLedgerStore.addIncome(amount: 240.50, clientID: entity.id, project: "", task: "Delivery", currencyCode: "RUB")
        let saved = try #require(context.fetch(FetchDescriptor<Entry>()).first)
        #expect(saved.client?.id == client.id)
        #expect(saved.currencyCode == "RUB")
        #expect(saved.amount == 240.50)
        #expect(saved.needsSync)
        #expect(app.mutations.dataRevision > before)
        app.workspaceStoreIdentity = "another-workspace"
        await #expect(throws: IntentLedgerError.self) {
            try await IntentLedgerStore.addIncome(amount: 100, clientID: entity.id, project: "", task: "Wrong workspace")
        }
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        app.requireAppLock = true
        #expect(IntentLedgerStore.clients().isEmpty)
    }

    @Test func quickActionsConsumeOnceAndUnknownURLsDoNothing() async throws {
        let defaults = try #require(UserDefaults(suiteName: "quick-actions-\(UUID())"))
        let app = AppModel(defaults: defaults)
        defaults.set("search", forKey: EarnlineAppDelegate.pendingQuickActionKey)
        app.consumeQuickAction()
        #expect(app.pendingQuickAction == .search)
        #expect(defaults.string(forKey: EarnlineAppDelegate.pendingQuickActionKey) == nil)
        app.pendingQuickAction = nil
        app.consumeQuickAction()
        #expect(app.pendingQuickAction == nil)
        await app.handleAppURL(try #require(URL(string: "unknown://add-income")))
        #expect(app.pendingQuickAction == nil)
        let url = try #require(URL(string: "\(AppModel.oauthRedirectURL.scheme!)://add-income"))
        await app.handleAppURL(url)
        #expect(app.pendingQuickAction == .addIncome)
    }

    @Test func latestReminderStateWinsAfterAnOlderAddFinishes() async {
        let center = TestReminderCenter()
        let scheduler = PendingReminderScheduler(center: center)
        let request = PendingNotifications.Request(id: UUID().uuidString,
            dateComponents: DateComponents(year: 2030, month: 1, day: 1, hour: 9), body: "Old details")
        center.onAdd = { scheduler.submit([]) }
        scheduler.submit([request])
        await scheduler.flush()
        #expect(center.requests.isEmpty)
        #expect(center.addCount == 1)
    }

    @Test func matchingRemindersAreNotRescheduled() async {
        let center = TestReminderCenter()
        let scheduler = PendingReminderScheduler(center: center)
        let request = PendingNotifications.Request(id: UUID().uuidString,
            dateComponents: DateComponents(year: 2030, month: 1, day: 1, hour: 9), body: "Delivery")
        scheduler.submit([request])
        await scheduler.flush()
        scheduler.submit([request])
        await scheduler.flush()
        #expect(center.addCount == 1)
        #expect(center.requests.count == 1)
    }

    @Test func oversizedFileIsRejectedBeforeImport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(LedgerImportFile.maximumBytes + 1))
        try handle.close()
        #expect(throws: LedgerImportFile.ReadError.self) { try LedgerImportFile.read(url) }
    }

    @Test func widgetSnapshotKeepsBothLiveCurrencyDisplays() throws {
        let original = LedgerWidgetSnapshot(date: .now, month: "September", primary: "$100", secondary: "8 300 ₽", hidesAmounts: false)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(LedgerWidgetSnapshot.self, from: data)
        #expect(restored.primary == "$100")
        #expect(restored.secondary == "8 300 ₽")
        #expect(!restored.hidesAmounts)
    }
}

@MainActor
private final class TestReminderCenter: PendingReminderCenter {
    var requests: [String: UNNotificationRequest] = [:]
    var onAdd: (() -> Void)?
    var addCount = 0
    func authorization() async -> UNAuthorizationStatus { .authorized }
    func requestPermission() async throws -> Bool { true }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func remove(identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func add(_ request: UNNotificationRequest) async throws {
        onAdd?()
        await Task.yield()
        requests[request.identifier] = request
        addCount += 1
    }
}
