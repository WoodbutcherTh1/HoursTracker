import XCTest
@testable import HoursTracker

final class SyncMergeTests: XCTestCase {
    func testRemoteOnlySessionIsAdded() {
        let local = TestData.session(day: 1)
        let remote = TestData.session(day: 2)

        let merged = CloudKitSyncManager.mergeSessions(local: [local], remote: [remote])

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(local))
        XCTAssertTrue(merged.contains(remote))
    }

    func testNewerLocalSessionWinsConflict() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        var localSession = TestData.session(day: 1, id: id, modifiedAt: newer)
        localSession.notes = "local"
        var remoteSession = TestData.session(day: 1, id: id, modifiedAt: older)
        remoteSession.notes = "remote"

        let merged = CloudKitSyncManager.mergeSessions(local: [localSession], remote: [remoteSession])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.notes, "local")
    }

    func testNewerRemoteSessionWinsConflict() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        var localSession = TestData.session(day: 1, id: id, modifiedAt: older)
        localSession.notes = "local"
        var remoteSession = TestData.session(day: 1, id: id, modifiedAt: newer)
        remoteSession.notes = "remote"

        let merged = CloudKitSyncManager.mergeSessions(local: [localSession], remote: [remoteSession])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.notes, "remote")
    }

    func testEqualTimestampsPreferLocal() {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        var localSession = TestData.session(day: 1, id: id, modifiedAt: timestamp)
        localSession.notes = "local"
        var remoteSession = TestData.session(day: 1, id: id, modifiedAt: timestamp)
        remoteSession.notes = "remote"

        let merged = CloudKitSyncManager.mergeSessions(local: [localSession], remote: [remoteSession])

        XCTAssertEqual(merged.first?.notes, "local")
    }

    func testMissingRemoteSettingsFallsBackToLocal() {
        let local = TestData.settings()

        let merged = CloudKitSyncManager.mergeSettings(local: local, remote: nil)

        XCTAssertEqual(merged, local)
    }

    func testNewerRemoteSettingsWin() {
        var local = TestData.settings()
        local.modifiedAt = Date(timeIntervalSince1970: 1_000)
        var remote = TestData.settings()
        remote.workplaceName = "Remote"
        remote.modifiedAt = Date(timeIntervalSince1970: 2_000)

        let merged = CloudKitSyncManager.mergeSettings(local: local, remote: remote)

        XCTAssertEqual(merged.workplaceName, "Remote")
    }

    func testSettingsMergeKeepsLocalNationalIDEvenWhenRemoteWins() {
        var local = TestData.settings()
        local.workerIDNumber = "local-id"
        local.modifiedAt = Date(timeIntervalSince1970: 1_000)
        var remote = TestData.settings()
        remote.workerIDNumber = "remote-id"
        remote.workplaceName = "Remote"
        remote.modifiedAt = Date(timeIntervalSince1970: 2_000)

        let merged = CloudKitSyncManager.mergeSettings(local: local, remote: remote)

        XCTAssertEqual(merged.workplaceName, "Remote")
        XCTAssertEqual(merged.workerIDNumber, "local-id")
    }

    func testTombstonedRemoteSessionIsNotResurrected() {
        let deletedID = UUID()
        let survivor = TestData.session(day: 1)
        let ghost = TestData.session(day: 2, id: deletedID)
        let otherRemote = TestData.session(day: 3)

        let merged = CloudKitSyncManager.mergeSessions(
            local: [survivor],
            remote: [ghost, otherRemote],
            tombstoneIDs: [deletedID]
        )

        XCTAssertEqual(Set(merged.map(\.id)), Set([survivor.id, otherRemote.id]))
        XCTAssertFalse(merged.contains { $0.id == deletedID })
    }

    func testTombstoneRemovesStaleLocalCopy() {
        let deletedID = UUID()
        let staleLocal = TestData.session(day: 1, id: deletedID)
        let remoteOther = TestData.session(day: 2)

        let merged = CloudKitSyncManager.mergeSessions(
            local: [staleLocal],
            remote: [remoteOther],
            tombstoneIDs: [deletedID]
        )

        XCTAssertEqual(merged.map(\.id), [remoteOther.id])
    }

    func testConflictResolverPrefersNewerModifiedAt() {
        let older = Date(timeIntervalSince1970: 1)
        let newer = Date(timeIntervalSince1970: 2)
        let intended = "intended"
        let server = "server"

        XCTAssertEqual(
            CloudKitSyncManager.resolveConflictWinner(
                intendedModifiedAt: newer,
                serverModifiedAt: older,
                intended: intended,
                server: server
            ),
            "intended"
        )
        XCTAssertEqual(
            CloudKitSyncManager.resolveConflictWinner(
                intendedModifiedAt: older,
                serverModifiedAt: newer,
                intended: intended,
                server: server
            ),
            "server"
        )
        XCTAssertEqual(
            CloudKitSyncManager.resolveConflictWinner(
                intendedModifiedAt: newer,
                serverModifiedAt: newer,
                intended: intended,
                server: server
            ),
            "intended"
        )
    }
}
