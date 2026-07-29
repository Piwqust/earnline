import Foundation
import SwiftData
import Supabase
import Testing
@testable import earnline

/// End-to-end `SyncCoordinator.sync` passes against a canned PostgREST
/// transport: a `URLProtocol` mock serves each table's rows and records every
/// request, locking in the push/pull/tombstone ordering without a live server.
///
/// Serialized because the mock transport is process-global (URLProtocol has no
/// per-instance routing).
@MainActor
@Suite(.serialized)
struct SyncCoordinatorTests {
    // MARK: Mock transport

    /// Routes PostgREST requests by "METHOD table" and records them in order.
    final class MockTransport: URLProtocol {
        struct Recorded: Sendable {
            let method: String
            let table: String
            let query: String
            let body: String
        }

        private static let lock = NSLock()
        nonisolated(unsafe) private static var responses: [String: Data] = [:]
        nonisolated(unsafe) private static var recordedRequests: [Recorded] = []

        static func reset() {
            lock.lock(); defer { lock.unlock() }
            responses = [:]
            recordedRequests = []
        }

        static func respond(_ method: String, _ table: String, json: String) {
            lock.lock(); defer { lock.unlock() }
            responses["\(method) \(table)"] = Data(json.utf8)
        }

        static var recorded: [Recorded] {
            lock.lock(); defer { lock.unlock() }
            return recordedRequests
        }

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let method = request.httpMethod ?? "GET"
            let table = request.url?.lastPathComponent ?? ""
            let record = Recorded(method: method,
                                  table: table,
                                  query: request.url?.query ?? "",
                                  body: Self.bodyString(of: request))
            let data: Data
            Self.lock.lock()
            Self.recordedRequests.append(record)
            data = Self.responses["\(method) \(table)"] ?? Data("[]".utf8)
            Self.lock.unlock()

            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        /// URLSession moves `httpBody` into a stream before the protocol sees
        /// it, so read whichever is populated.
        private static func bodyString(of request: URLRequest) -> String {
            if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
            guard let stream = request.httpBodyStream else { return "" }
            stream.open(); defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    // MARK: Fixtures

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Client.self, Entry.self, Heading.self, SyncTombstone.self, ProjectIconPreference.self, MonthReview.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeClient() -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTransport.self]
        return SupabaseClient(
            supabaseURL: URL(string: "https://mock.supabase.co")!,
            supabaseKey: "test-key",
            options: SupabaseClientOptions(
                auth: .init(autoRefreshToken: false),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }

    private let workspace = "test-workspace"

    private func timestamp(_ value: String) -> Date {
        SyncDateCodec.parseTimestamp(value)!
    }

    // MARK: Pull

    @Test func workspaceProfileSeedsCloudWithPrecisionSafeCurrencyTuple() async throws {
        MockTransport.reset()
        MockTransport.respond("POST", "earnline_profiles", json: """
        {"workspace_id":"\(workspace)","base_currency_code":"USD",
          "secondary_currency_code":"RUB","exchange_rate":"89.125",
          "updated_at":"2026-07-11T08:00:00.000Z"}
        """)

        let payload = WorkspaceProfilePayload(workspaceID: workspace,
                                              baseCurrencyCode: "USD",
                                              secondaryCurrencyCode: "RUB",
                                              exchangeRate: 89.125)
        let profile = try await SyncCoordinator.syncWorkspaceProfile(
            client: makeClient(),
            workspaceID: workspace,
            local: payload,
            pushLocal: true
        )

        #expect(profile.exchangeRate.decimal == Decimal(string: "89.125"))
        let request = try #require(MockTransport.recorded.first { $0.method == "POST" })
        #expect(request.table == "earnline_profiles")
        #expect(request.body.contains("\"exchange_rate\":\"89.125\""))
        #expect(request.query.contains("on_conflict=workspace_id"))
    }

    @Test func workspaceProfilePullsCloudWithoutOverwritingItOnLaunch() async throws {
        MockTransport.reset()
        MockTransport.respond("GET", "earnline_profiles", json: """
        [{"workspace_id":"\(workspace)","base_currency_code":"USD",
          "secondary_currency_code":"RUB","exchange_rate":"72.5",
          "updated_at":"2026-07-13T00:00:00.000Z"}]
        """)

        let local = WorkspaceProfilePayload(workspaceID: workspace,
                                            baseCurrencyCode: "EUR",
                                            secondaryCurrencyCode: "GBP",
                                            exchangeRate: 89.125)
        let profile = try await SyncCoordinator.syncWorkspaceProfile(
            client: makeClient(),
            workspaceID: workspace,
            local: local,
            pushLocal: false
        )

        #expect(profile.exchangeRate.decimal == Decimal(string: "72.5"))
        #expect(profile.baseCurrencyCode == "USD")
        #expect(MockTransport.recorded.contains { $0.method == "GET" && $0.table == "earnline_profiles" })
        #expect(!MockTransport.recorded.contains { $0.method == "POST" && $0.table == "earnline_profiles" })
    }

    @Test func pullInsertsRemoteRowsAndAdvancesCursor() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let clientID = UUID()
        let entryID = UUID()
        MockTransport.respond("GET", "earnline_clients", json: """
        [{"id":"\(clientID.uuidString)","workspace_id":"\(workspace)","name":"Acme",
          "color_hex":"#0088FF","sort_index":1,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-01T10:00:00.000Z"}]
        """)
        MockTransport.respond("GET", "earnline_entries", json: """
        [{"id":"\(entryID.uuidString)","workspace_id":"\(workspace)",
          "client_id":"\(clientID.uuidString)","amount":"99.50","currency_code":"USD",
          "project":"Site","task":"Landing page","date":"2026-06-15","hold_until":null,
          "status":"paid","sort_index":0,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-02T10:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(context: context,
                                                    client: makeClient(),
                                                    workspaceID: workspace)

        let client = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(client.id == clientID)
        #expect(client.name == "Acme")
        #expect(client.syncState == .synced)

        let entry = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.id == entryID)
        #expect(entry.amount == Decimal(string: "99.50"))
        #expect(entry.client?.id == clientID)
        #expect(entry.status == .paid)
        #expect(entry.syncState == .synced)
        let day = Calendar.current.dateComponents([.year, .month, .day], from: entry.date)
        #expect(day.year == 2026 && day.month == 6 && day.day == 15)

        // Cursor is the newest observed server stamp, not the local clock.
        #expect(cursor.rowUpdatedAt == timestamp("2026-07-02T10:00:00.000Z"))
    }

    @Test func pulledEntryWithoutItsClientIsSkipped() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        MockTransport.respond("GET", "earnline_entries", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)",
          "client_id":"\(UUID().uuidString)","amount":"10.00","currency_code":"USD",
          "project":null,"task":"Orphan","date":"2026-06-15","hold_until":null,
          "status":"paid","sort_index":0,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-01T10:00:00.000Z"}]
        """)

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
    }

    @Test func pullInsertsProjectIconAndAdvancesCursor() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext
        let id = try #require(ProjectIconResolver.preferenceID(for: "Launch Kit"))

        MockTransport.respond("GET", "earnline_project_icons", json: """
        [{"id":"\(id.uuidString)","workspace_id":"\(workspace)",
          "project_key":"launch kit","symbol_name":"paintpalette",
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-04T10:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(
            context: context,
            client: makeClient(),
            workspaceID: workspace
        )

        let preference = try #require(
            try context.fetch(FetchDescriptor<ProjectIconPreference>()).first
        )
        #expect(preference.id == id)
        #expect(preference.projectKey == "launch kit")
        #expect(preference.symbol == .paintpalette)
        #expect(preference.syncState == .synced)
        #expect(cursor.rowUpdatedAt == timestamp("2026-07-04T10:00:00.000Z"))
    }

    @Test func pullInsertsMonthReviewAndAdvancesCursor() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext
        let monthStart = try #require(SyncDateCodec.parseDay("2026-01-01"))
        let id = MonthReview.id(for: monthStart)

        MockTransport.respond("GET", "earnline_month_reviews", json: """
        [{"id":"\(id.uuidString)","workspace_id":"\(workspace)",
          "month_start":"2026-01-01","note":"Closed after delivery",
          "closed_at":"2026-02-01T12:00:00.000Z",
          "created_at":"2026-02-01T09:00:00.000Z","updated_at":"2026-02-02T10:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(
            context: context,
            client: makeClient(),
            workspaceID: workspace
        )

        let review = try #require(try context.fetch(FetchDescriptor<MonthReview>()).first)
        #expect(review.id == id)
        #expect(SyncDateCodec.dayString(review.monthStart) == "2026-01-01")
        #expect(review.note == "Closed after delivery")
        #expect(review.closedAt == timestamp("2026-02-01T12:00:00.000Z"))
        #expect(review.syncState == .synced)
        #expect(cursor.rowUpdatedAt == timestamp("2026-02-02T10:00:00.000Z"))
    }

    @Test func cloudReopenClearsAnExistingMonthReviewCloseDate() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext
        let monthStart = try #require(SyncDateCodec.parseDay("2026-01-01"))
        let id = MonthReview.id(for: monthStart)
        let existing = MonthReview(
            id: id,
            monthStart: monthStart,
            note: "Locally closed",
            closedAt: timestamp("2026-02-01T12:00:00.000Z"),
            createdAt: timestamp("2026-02-01T09:00:00.000Z"),
            updatedAt: timestamp("2026-02-01T12:00:00.000Z"),
            syncState: .synced,
            lastSyncedAt: timestamp("2026-02-01T12:00:00.000Z")
        )
        context.insert(existing)
        try context.save()

        MockTransport.respond("GET", "earnline_month_reviews", json: """
        [{"id":"\(id.uuidString)","workspace_id":"\(workspace)",
          "month_start":"2026-01-01","note":"Cloud reopened",
          "closed_at":null,
          "created_at":"2026-02-01T09:00:00.000Z","updated_at":"2026-02-03T10:00:00.000Z"}]
        """)

        _ = try await SyncCoordinator.sync(
            context: context,
            client: makeClient(),
            workspaceID: workspace
        )

        #expect(existing.note == "Cloud reopened")
        #expect(existing.closedAt == nil)
        #expect(existing.syncState == .synced)
    }

    @Test func malformedRemoteRowsAreSkippedNotDefaulted() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let goodID = UUID()
        MockTransport.respond("GET", "earnline_clients", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","name":"Broken",
          "color_hex":"#000000","sort_index":0,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"not-a-date"},
         {"id":"\(goodID.uuidString)","workspace_id":"\(workspace)","name":"Valid",
          "color_hex":"#0088FF","sort_index":1,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-03T08:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(context: context,
                                                    client: makeClient(),
                                                    workspaceID: workspace)

        let clients = try context.fetch(FetchDescriptor<Client>())
        #expect(clients.count == 1)
        #expect(clients.first?.name == "Valid")
        // The malformed stamp must not poison the cursor either.
        #expect(cursor.rowUpdatedAt == timestamp("2026-07-03T08:00:00.000Z"))
    }

    // MARK: Push

    @Test func pushUpsertsDirtyRowsAndMarksThemSynced() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let client = Client(name: "Acme")
        let entry = Entry(amount: 240, task: "2 screens")
        let projectIcon = ProjectIconPreference(
            id: ProjectIconResolver.preferenceID(for: "Site")!,
            projectKey: ProjectIconResolver.normalizedKey(for: "Site"),
            symbol: .display
        )
        let monthReview = MonthReview(
            monthStart: timestamp("2026-01-01T12:00:00.000Z"),
            note: "January closed",
            closedAt: timestamp("2026-02-01T12:00:00.000Z")
        )
        entry.client = client
        context.insert(client)
        context.insert(entry)
        context.insert(projectIcon)
        context.insert(monthReview)
        try context.save()

        let cursor = try await SyncCoordinator.sync(context: context,
                                                    client: makeClient(),
                                                    workspaceID: workspace)

        let posts = MockTransport.recorded.filter { $0.method == "POST" }
        #expect(posts.contains { $0.table == "earnline_clients" && $0.body.contains("Acme") })
        #expect(posts.contains { $0.table == "earnline_entries" && $0.body.contains("2 screens") })
        #expect(posts.contains {
            $0.table == "earnline_project_icons"
                && $0.body.contains("site")
                && $0.body.contains("display")
        })
        #expect(posts.contains {
            $0.table == "earnline_month_reviews"
                && $0.body.contains("2026-01-01")
                && $0.body.contains("January closed")
        })

        #expect(try context.fetch(FetchDescriptor<Client>()).first?.syncState == .synced)
        #expect(try context.fetch(FetchDescriptor<Entry>()).first?.syncState == .synced)
        #expect(try context.fetch(FetchDescriptor<ProjectIconPreference>()).first?.syncState == .synced)
        #expect(try context.fetch(FetchDescriptor<MonthReview>()).first?.syncState == .synced)
        // Nothing was pulled, so there is no observed server stamp to advance to.
        #expect(cursor.rowUpdatedAt == nil)
    }

    @Test func pushSplits1001DirtyClientsIntoSafeBatches() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        for index in 0...1000 {
            context.insert(Client(name: "Client \(index)"))
        }
        try context.save()

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace)

        let clientUpserts = MockTransport.recorded.filter {
            $0.method == "POST" && $0.table == "earnline_clients"
        }
        let batchSizes = try clientUpserts.map { request -> Int in
            let payload = try #require(
                JSONSerialization.jsonObject(with: Data(request.body.utf8)) as? [[String: Any]]
            )
            return payload.count
        }
        #expect(batchSizes == [250, 250, 250, 250, 1])
    }

    @Test func localTombstoneIsPushedThenCleared() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let deletedEntryID = UUID()
        SyncDeleteQueue.enqueue(.entry, id: deletedEntryID, in: context)
        try context.save()

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace)

        let recorded = MockTransport.recorded
        #expect(recorded.contains {
            $0.method == "POST" && $0.table == "earnline_tombstones"
                && $0.body.lowercased().contains(deletedEntryID.uuidString.lowercased())
        })
        #expect(recorded.contains {
            $0.method == "DELETE" && $0.table == "earnline_entries"
                && $0.query.contains("workspace_id")
        })
        // Delivered tombstones don't linger locally.
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    // MARK: Ordering

    @Test func remoteClientTombstoneCascadesBeforePush() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        // A synced client with a *dirty* entry — deleted on another device.
        // The tombstone must land before the push so the doomed entry is
        // never upserted (its remote FK row is already gone).
        // `lastSyncedAt` is the server version this device last observed, and it
        // must predate the tombstone — a row deleted remotely at 07-05 cannot
        // also have been seen alive afterwards. The tombstone-vs-restore rule
        // compares against exactly this value.
        let client = Client(name: "Gone",
                            createdAt: timestamp("2026-07-01T09:00:00.000Z"),
                            updatedAt: timestamp("2026-07-01T09:00:00.000Z"),
                            syncState: .synced,
                            lastSyncedAt: timestamp("2026-07-01T09:00:00.000Z"))
        let entry = Entry(amount: 50, task: "orphaned edit")
        entry.client = client
        context.insert(client)
        context.insert(entry)
        try context.save()

        MockTransport.respond("GET", "earnline_tombstones", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","entity":"client",
          "record_id":"\(client.id.uuidString)",
          "deleted_at":"2026-07-05T12:00:00.000Z","created_at":"2026-07-05T12:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(context: context,
                                                    client: makeClient(),
                                                    workspaceID: workspace)

        #expect(try context.fetch(FetchDescriptor<Client>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        // The cascade-deleted entry must not have been pushed.
        #expect(!MockTransport.recorded.contains { $0.method == "POST" && $0.table == "earnline_entries" })
        // Device-originated tombstone dates never advance the row cursor.
        #expect(cursor.rowUpdatedAt == nil)
    }

    @Test func malformedTombstoneDeletesNothing() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let client = Client(name: "Keep",
                            createdAt: .now,
                            updatedAt: .now,
                            syncState: .synced,
                            lastSyncedAt: .now)
        context.insert(client)
        try context.save()

        MockTransport.respond("GET", "earnline_tombstones", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","entity":"client",
          "record_id":"\(client.id.uuidString)",
          "deleted_at":"not-a-date","created_at":"2026-07-05T12:00:00.000Z"}]
        """)

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace)
        #expect(try context.fetch(FetchDescriptor<Client>()).count == 1)
    }

    @Test func newerCloudEditConflictsBeforeThisIPhonePushes() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext
        let baseline = timestamp("2026-07-01T10:00:00.000Z")
        let client = Client(name: "Local edit",
                            createdAt: baseline,
                            updatedAt: timestamp("2026-07-02T10:00:00.000Z"),
                            syncState: .dirty,
                            lastSyncedAt: baseline)
        context.insert(client)
        try context.save()

        MockTransport.respond("GET", "earnline_clients", json: """
        [{"id":"\(client.id.uuidString)","workspace_id":"\(workspace)","name":"Cloud edit",
          "color_hex":"#0088FF","sort_index":1,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-03T10:00:00.000Z"}]
        """)

        await #expect(throws: SyncCoordinator.SyncConflictError.detected(1)) {
            try await SyncCoordinator.sync(context: context,
                                            client: makeClient(),
                                            workspaceID: workspace)
        }

        #expect(client.name == "Local edit")
        #expect(!MockTransport.recorded.contains {
            $0.method == "POST" && $0.table == "earnline_clients"
        })
    }

    @Test func newerCloudProjectIconConflictsBeforeThisIPhonePushes() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext
        let baseline = timestamp("2026-07-01T10:00:00.000Z")
        let id = try #require(ProjectIconResolver.preferenceID(for: "Site"))
        let preference = ProjectIconPreference(
            id: id,
            projectKey: "site",
            symbol: .camera,
            createdAt: baseline,
            updatedAt: timestamp("2026-07-02T10:00:00.000Z"),
            syncState: .dirty,
            lastSyncedAt: baseline
        )
        context.insert(preference)
        try context.save()

        MockTransport.respond("GET", "earnline_project_icons", json: """
        [{"id":"\(id.uuidString)","workspace_id":"\(workspace)",
          "project_key":"site","symbol_name":"video",
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-03T10:00:00.000Z"}]
        """)

        await #expect(throws: SyncCoordinator.SyncConflictError.detected(1)) {
            try await SyncCoordinator.sync(
                context: context,
                client: makeClient(),
                workspaceID: workspace
            )
        }

        #expect(preference.symbol == .camera)
        #expect(!MockTransport.recorded.contains {
            $0.method == "POST" && $0.table == "earnline_project_icons"
        })
    }

    @Test func oldTombstoneStillAppliesEvenAfterTheRowCursorAdvanced() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext
        let client = Client(name: "Deleted long ago", syncState: .synced,
                            lastSyncedAt: timestamp("2020-01-01T00:00:00.000Z"))
        context.insert(client)
        try context.save()

        MockTransport.respond("GET", "earnline_tombstones", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","entity":"client",
          "record_id":"\(client.id.uuidString)",
          "deleted_at":"2020-01-02T00:00:00.000Z","created_at":"2020-01-02T00:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(context: context,
                                                     client: makeClient(),
                                                     workspaceID: workspace,
                                                     lastPulledAt: timestamp("2026-07-01T00:00:00.000Z"))

        #expect(try context.fetch(FetchDescriptor<Client>()).isEmpty)
        #expect(cursor.rowUpdatedAt == timestamp("2026-07-01T00:00:00.000Z"))
    }

    // MARK: Restore over a retained tombstone

    /// Tombstones are append-only and replayed in full, so a row that was
    /// deleted and then restored is still named by its own tombstone forever.
    /// The restore wins because its server `updated_at` — recorded in
    /// `lastSyncedAt` by the post-push pull — lands after the deletion.
    ///
    /// Before the tombstone-vs-restore comparison existed, this row was deleted
    /// again on the pass after the user chose to keep it, while it still existed
    /// in Postgres: silent local data loss plus a permanent divergence.
    @Test func restoredRowSurvivesItsOwnRetainedTombstone() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let restoredAt = timestamp("2026-07-10T10:00:00.000Z")
        let client = Client(name: "Restored",
                            createdAt: timestamp("2026-07-01T09:00:00.000Z"),
                            updatedAt: restoredAt,
                            syncState: .synced,
                            lastSyncedAt: restoredAt)
        context.insert(client)
        try context.save()

        // The delete that was pushed before the user hit Undo. It is never
        // pruned, so every later pass sees it again.
        MockTransport.respond("GET", "earnline_tombstones", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","entity":"client",
          "record_id":"\(client.id.uuidString)",
          "deleted_at":"2026-07-05T12:00:00.000Z","created_at":"2026-07-05T12:00:00.000Z"}]
        """)
        // No `earnline_clients` response: the cursor has already advanced past
        // this row, so the incremental pull returns nothing for it. That is what
        // makes the old behaviour permanent — the tombstone deleted the row and
        // no later pull ever brought it back, while it still existed remotely.
        let cursorPastTheRestore = timestamp("2026-07-20T00:00:00.000Z")

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace,
                                           lastPulledAt: cursorPastTheRestore)

        let survivors = try context.fetch(FetchDescriptor<Client>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.name == "Restored")
    }

    /// The mirror case: a row whose server copy is *older* than its tombstone
    /// was left behind by a partially completed delete. The pull must not
    /// resurrect it, or it would flap — deleted by the tombstone loop, then
    /// re-inserted by the pull — on every single pass.
    @Test func rowOlderThanItsTombstoneIsNotResurrectedByThePull() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let orphanID = UUID()
        MockTransport.respond("GET", "earnline_tombstones", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","entity":"client",
          "record_id":"\(orphanID.uuidString)",
          "deleted_at":"2026-07-05T12:00:00.000Z","created_at":"2026-07-05T12:00:00.000Z"}]
        """)
        MockTransport.respond("GET", "earnline_clients", json: """
        [{"id":"\(orphanID.uuidString)","workspace_id":"\(workspace)","name":"Half-deleted",
          "color_hex":"#0088FF","sort_index":0,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-04T09:00:00.000Z"}]
        """)

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace)

        #expect(try context.fetch(FetchDescriptor<Client>()).isEmpty)
    }

    /// A skipped row is still an *observed* server version: the cursor has to
    /// advance past it, or every later pass would re-fetch and re-skip it.
    @Test func skippedTombstonedRowStillAdvancesTheCursor() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let orphanID = UUID()
        MockTransport.respond("GET", "earnline_tombstones", json: """
        [{"id":"\(UUID().uuidString)","workspace_id":"\(workspace)","entity":"client",
          "record_id":"\(orphanID.uuidString)",
          "deleted_at":"2026-07-05T12:00:00.000Z","created_at":"2026-07-05T12:00:00.000Z"}]
        """)
        MockTransport.respond("GET", "earnline_clients", json: """
        [{"id":"\(orphanID.uuidString)","workspace_id":"\(workspace)","name":"Half-deleted",
          "color_hex":"#0088FF","sort_index":0,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-04T09:00:00.000Z"}]
        """)

        let cursor = try await SyncCoordinator.sync(context: context,
                                                     client: makeClient(),
                                                     workspaceID: workspace)

        #expect(cursor.rowUpdatedAt == timestamp("2026-07-04T09:00:00.000Z"))
    }

    // MARK: Request shaping

    /// `in (…)` ids travel in the URL. One unbounded DELETE for a large batch
    /// (a client and all its entries) exceeded the request line, the server
    /// answered 414, and every retry rebuilt the identical request.
    @Test func largeDeleteBatchIsSplitAcrossRequests() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        for _ in 0..<250 {
            SyncDeleteQueue.enqueue(.entry, id: UUID(), in: context)
        }
        try context.save()

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace)

        let deletes = MockTransport.recorded.filter {
            $0.method == "DELETE" && $0.table == "earnline_entries"
        }
        // 250 ids at 100 per request.
        #expect(deletes.count == 3)
        // No single request may carry the whole batch.
        #expect(deletes.allSatisfy { $0.query.count < 8_000 })
        // Every tombstone still went out, and none linger locally.
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    /// The post-push pull only needs the server stamps for rows this pass just
    /// wrote. Re-running it from the original cursor re-fetched, re-decoded and
    /// re-merged the entire delta a second time on every single pass.
    @Test func postPushPullResumesFromTheFirstPullsCursor() async throws {
        MockTransport.reset()
        let container = try makeContainer()
        let context = container.mainContext

        let baseline = timestamp("2026-07-01T10:00:00.000Z")
        let client = Client(name: "Local", createdAt: baseline, updatedAt: baseline,
                            syncState: .synced, lastSyncedAt: baseline)
        context.insert(client)
        try context.save()

        MockTransport.respond("GET", "earnline_clients", json: """
        [{"id":"\(client.id.uuidString)","workspace_id":"\(workspace)","name":"Cloud",
          "color_hex":"#0088FF","sort_index":0,
          "created_at":"2026-07-01T09:00:00.000Z","updated_at":"2026-07-09T10:00:00.000Z"}]
        """)

        _ = try await SyncCoordinator.sync(context: context,
                                           client: makeClient(),
                                           workspaceID: workspace,
                                           lastPulledAt: baseline)

        let clientGets = MockTransport.recorded.filter {
            $0.method == "GET" && $0.table == "earnline_clients"
        }
        #expect(clientGets.count == 2)
        // The second pass starts from what the first observed (07-09), not from
        // the cursor this pass began with (07-01).
        #expect(clientGets[0].query != clientGets[1].query)
        #expect(clientGets[1].query.contains("2026-07-09"))
    }

    // MARK: Decision rules

    @Test func tombstoneLosesToANewerObservedServerVersion() {
        let deletedAt = timestamp("2026-07-05T12:00:00.000Z")
        // Restored and re-pushed after the delete — must survive.
        #expect(!SyncCoordinator.tombstoneApplies(
            deletedAt: deletedAt,
            localLastSyncedAt: timestamp("2026-07-10T10:00:00.000Z"),
            localSyncUpdatedAt: timestamp("2026-07-10T10:00:00.000Z"),
            localState: .synced
        ))
        // Deleted after this device last saw the row — must apply.
        #expect(SyncCoordinator.tombstoneApplies(
            deletedAt: deletedAt,
            localLastSyncedAt: timestamp("2026-07-01T10:00:00.000Z"),
            localSyncUpdatedAt: timestamp("2026-07-01T10:00:00.000Z"),
            localState: .synced
        ))
        // A dirty row is routed to a user choice, never silently deleted.
        #expect(!SyncCoordinator.tombstoneApplies(
            deletedAt: deletedAt,
            localLastSyncedAt: timestamp("2026-07-01T10:00:00.000Z"),
            localSyncUpdatedAt: timestamp("2026-07-01T10:00:00.000Z"),
            localState: .dirty
        ))
    }

    @Test func latestDeletionTimeWinsForARepeatedlyDeletedRow() {
        let recordID = UUID()
        func tombstone(_ deletedAt: String) -> RemoteTombstone {
            RemoteTombstone(
                SyncTombstone(entity: .entry, recordID: recordID, deletedAt: timestamp(deletedAt)),
                workspaceID: workspace
            )
        }
        let times = SyncCoordinator.latestDeletionTimes([
            tombstone("2026-07-01T00:00:00.000Z"),
            tombstone("2026-07-09T00:00:00.000Z"),
            tombstone("2026-07-05T00:00:00.000Z"),
        ])
        let key = SyncCoordinator.DeletionKey(entity: .entry, recordID: recordID)
        #expect(times[key] == timestamp("2026-07-09T00:00:00.000Z"))
    }
}
