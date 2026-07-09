import Foundation
import Testing
@testable import earnline

/// Locks in the sync conflict policy: clean rows accept cloud state, while a
/// dirty row is never overwritten automatically.
@MainActor
struct ConflictPolicyTests {
    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000_000 + offset)
    }

    @Test func cleanLocalAlwaysTakesRemoteEvenIfOlder() {
        #expect(SyncCoordinator.shouldApplyRemote(localState: .synced))
    }

    @Test func dirtyLocalWithUnchangedCloudVersionStaysLocalUntilPush() {
        #expect(!SyncCoordinator.conflictsWithDirtyLocal(
            remoteUpdatedAt: date(0), localLastSyncedAt: date(0), localState: .dirty))
        #expect(!SyncCoordinator.shouldApplyRemote(localState: .dirty))
    }

    @Test func newerCloudVersionRequiresAnExplicitChoice() {
        #expect(SyncCoordinator.conflictsWithDirtyLocal(
            remoteUpdatedAt: date(10), localLastSyncedAt: date(0), localState: .dirty))
    }

    @Test func missingServerBaselineFailsClosed() {
        #expect(SyncCoordinator.conflictsWithDirtyLocal(
            remoteUpdatedAt: date(0), localLastSyncedAt: nil, localState: .dirty))
    }
}
