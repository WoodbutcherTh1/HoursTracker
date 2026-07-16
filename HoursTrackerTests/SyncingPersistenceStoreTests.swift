import XCTest
@testable import HoursTracker

final class SyncingPersistenceStoreTests: XCTestCase {
    private var local: InMemoryStore!
    private var cloud: RecordingCloud!
    private var store: SyncingPersistenceStore!

    override func setUp() {
        super.setUp()
        local = InMemoryStore()
        cloud = RecordingCloud()
        store = SyncingPersistenceStore(local: local, cloud: cloud)
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
    }
}
