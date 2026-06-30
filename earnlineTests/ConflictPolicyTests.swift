import Foundation
import Testing
@testable import earnline

/// Locks in the sync conflict policy: last-write-wins, with unsynced local edits
/// protected, and ties resolving to remote. See `SyncCoordinator.shouldApplyRemote`.
@MainActor
struct ConflictPolicyTests {
    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000_000 + offset)
    }

    @Test func cleanLocalAlwaysTakesRemoteEvenIfOlder() {
        #expect(SyncCoordinator.shouldApplyRemote(
            remoteUpdatedAt: date(-10), localUpdatedAt: date(0), localState: .synced))
    }

    @Test func dirtyLocalKeepsStrictlyNewerLocalEdit() {
        #expect(!SyncCoordinator.shouldApplyRemote(
            remoteUpdatedAt: date(-10), localUpdatedAt: date(0), localState: .dirty))
    }

    @Test func dirtyLocalTakesNewerRemote() {
        #expect(SyncCoordinator.shouldApplyRemote(
            remoteUpdatedAt: date(10), localUpdatedAt: date(0), localState: .dirty))
    }

    @Test func equalTimestampsResolveToRemote() {
        #expect(SyncCoordinator.shouldApplyRemote(
            remoteUpdatedAt: date(0), localUpdatedAt: date(0), localState: .dirty))
    }
}
