import XCTest
@testable import HoursTracker

final class SyncingPersistenceStoreTests: XCTestCase {
    private var local: InMemoryStore!
    private var cloud: RecordingCloud!
    private var tombstones: InMemoryTombstoneStore!
    private var store: SyncingPersistenceStore!

    override func setUp() {
        super.setUp()
        local = InMemoryStore()
        cloud = RecordingCloud()
        tombstones = InMemoryTombstoneStore()
        store = SyncingPersistenceStore(
            local: local,
            cloud: cloud,
            syncPreference: InMemoryCloudSyncPreference(isEnabled: true),
            tombstones: tombstones
        )
    }

    func testFirstSaveUploadsAllSessions() throws {
        let sessions = [TestData.session(day: 1), TestData.session(day: 2)]
        let uploaded = expectation(description: "uploaded")
        cloud.onUpload = { uploaded.fulfill() }

        try store.saveSessions(sessions)

        wait(for: [uploaded], timeout: 2)
        XCTAssertEqual(cloud.uploadedBatches.count, 1)
        XCTAssertEqual(Set(cloud.uploadedBatches[0].map(\.id)), Set(sessions.map(\.id)))
        XCTAssertEqual(local.storedSessions.count, 2)
    }

    func testResaveUploadsOnlyModifiedSessions() throws {
        var first = TestData.session(day: 1)
        let second = TestData.session(day: 2)

        let firstUpload = expectation(description: "first upload")
        cloud.onUpload = { firstUpload.fulfill() }
        try store.saveSessions([first, second])
        wait(for: [firstUpload], timeout: 2)

        first.notes = "edited"
        first.touch()

        let secondUpload = expectation(description: "second upload")
        cloud.onUpload = { secondUpload.fulfill() }
        try store.saveSessions([first, second])
        wait(for: [secondUpload], timeout: 2)

        XCTAssertEqual(cloud.uploadedBatches.count, 2)
        XCTAssertEqual(cloud.uploadedBatches[1].map(\.id), [first.id])
    }

    func testDeletionIsPropagatedWithoutReuploadingSurvivors() throws {
        let kept = TestData.session(day: 1)
        let removed = TestData.session(day: 2)

        let upload = expectation(description: "upload")
        cloud.onUpload = { upload.fulfill() }
        try store.saveSessions([kept, removed])
        wait(for: [upload], timeout: 2)

        let deletion = expectation(description: "deletion")
        cloud.onDelete = { deletion.fulfill() }
        try store.saveSessions([kept])
        wait(for: [deletion], timeout: 2)

        XCTAssertEqual(cloud.deletedIDBatches, [[removed.id]])
        XCTAssertEqual(cloud.uploadedBatches.count, 1, "unchanged sessions should not be re-uploaded")
        XCTAssertEqual(local.storedSessions.map(\.id), [kept.id])
    }

    func testLocalSaveFailureThrowsAndSkipsCloud() {
        local.saveError = NSError(domain: "test", code: 1)

        XCTAssertThrowsError(try store.saveSessions([TestData.session(day: 1)]))
        XCTAssertTrue(cloud.uploadedBatches.isEmpty)
    }

    func testCloudSyncSupportedFollowsInjectedBackend() {
        XCTAssertTrue(store.isCloudSyncSupported)

        let localOnly = SyncingPersistenceStore(local: InMemoryStore(), cloud: NoOpCloudSyncManager.shared)
        XCTAssertFalse(localOnly.isCloudSyncSupported)
        XCTAssertEqual(localOnly.syncState, .unavailable)
    }

    func testSaveSettingsLocallyDoesNotUpload() throws {
        let settings = TestData.settings()
        try store.saveSettingsLocally(settings)

        // Give any accidental Task a moment; upload must stay empty.
        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(local.storedSettings, settings)
        XCTAssertEqual(cloud.uploadedSettingsCount, 0)
        XCTAssertTrue(cloud.uploadedBatches.isEmpty)
    }

    func testPurgeCloudDataForwardsSessionIDs() async throws {
        let ids: Set<UUID> = [UUID(), UUID()]
        try await store.purgeCloudData(sessionIDs: ids)
        XCTAssertEqual(cloud.purgeCallCount, 1)
        XCTAssertEqual(cloud.lastPurgedSessionIDs, ids)
        XCTAssertEqual(tombstones.tombstoneIDs, ids)
    }

    func testLocalDeletionRecordsTombstoneEvenWhenSyncDisabled() throws {
        let kept = TestData.session(day: 1)
        let removed = TestData.session(day: 2)
        local.storedSessions = [kept, removed]
        store = SyncingPersistenceStore(
            local: local,
            cloud: cloud,
            syncPreference: InMemoryCloudSyncPreference(isEnabled: false),
            tombstones: tombstones
        )

        try store.saveSessions([kept])

        XCTAssertEqual(tombstones.tombstoneIDs, [removed.id])
        XCTAssertTrue(cloud.deletedIDBatches.isEmpty)
    }

    func testSyncRetriesWithLatestLocalDataWhenSaveFinishesDuringSync() async throws {
        let originalModifiedAt = TestData.date(2026, 1, 1, 8)
        let original = TestData.session(day: 1, outHour: nil, modifiedAt: originalModifiedAt)
        var initialSettings = TestData.settings(hourlyRate: 100)
        initialSettings.modifiedAt = originalModifiedAt
        local.storedSessions = [original]
        local.storedSettings = initialSettings
        cloud.syncResultProvider = { localSessions, localSettings, _ in
            SyncResult(sessions: localSessions, settings: localSettings)
        }

        let firstSyncPaused = expectation(description: "first sync paused before returning")
        let lock = NSLock()
        var shouldPauseFirstSync = true
        var resumeFirstSync: CheckedContinuation<Void, Never>?
        cloud.beforeSyncReturns = {
            lock.lock()
            guard shouldPauseFirstSync else {
                lock.unlock()
                return
            }
            shouldPauseFirstSync = false
            lock.unlock()

            await withCheckedContinuation { continuation in
                lock.lock()
                resumeFirstSync = continuation
                lock.unlock()
                firstSyncPaused.fulfill()
            }
        }

        let syncTask = Task {
            try await store.syncNow()
        }
        await fulfillment(of: [firstSyncPaused], timeout: 2)

        var closed = original
        closed.clockOut = TestData.date(2026, 1, 1, 17)
        closed.modifiedAt = originalModifiedAt.addingTimeInterval(60)
        var editedSettings = initialSettings
        editedSettings.hourlyRate = 200
        editedSettings.modifiedAt = originalModifiedAt.addingTimeInterval(60)
        try store.saveSessions([closed])
        try store.saveSettings(editedSettings)

        lock.lock()
        let continuation = resumeFirstSync
        lock.unlock()
        try XCTUnwrap(continuation).resume()

        let result = try await syncTask.value

        XCTAssertEqual(cloud.syncCallCount, 2)
        XCTAssertEqual(local.storedSessions.first?.clockOut, closed.clockOut)
        XCTAssertEqual(local.storedSessions.first?.modifiedAt, Optional(closed.modifiedAt))
        XCTAssertEqual(local.storedSettings.hourlyRate, editedSettings.hourlyRate)
        XCTAssertEqual(result.sessions.first?.clockOut, closed.clockOut)
        XCTAssertEqual(result.settings.hourlyRate, editedSettings.hourlyRate)
    }
}
