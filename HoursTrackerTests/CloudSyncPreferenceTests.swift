import XCTest
@testable import HoursTracker

final class CloudSyncPreferenceTests: XCTestCase {
    private var preference: InMemoryCloudSyncPreference!
    private var local: InMemoryStore!
    private var cloud: RecordingCloud!
    private var store: SyncingPersistenceStore!

    override func setUp() {
        super.setUp()
        preference = InMemoryCloudSyncPreference(isEnabled: false)
        local = InMemoryStore()
        cloud = RecordingCloud()
        store = SyncingPersistenceStore(local: local, cloud: cloud, syncPreference: preference)
    }

    func testDefaultPreferenceIsOff() {
        let defaults = UserDefaults(suiteName: "CloudSyncPreferenceTests-\(UUID().uuidString)")!
        let pref = UserDefaultsCloudSyncPreference(defaults: defaults)
        XCTAssertFalse(pref.isEnabled)
    }

    func testSaveSessionsDoesNotUploadWhenSyncDisabled() throws {
        let uploaded = expectation(description: "should not upload")
        uploaded.isInverted = true
        cloud.onUpload = { uploaded.fulfill() }

        try store.saveSessions([TestData.session(day: 1)])

        wait(for: [uploaded], timeout: 0.3)
        XCTAssertTrue(cloud.uploadedBatches.isEmpty)
        XCTAssertEqual(local.storedSessions.count, 1)
    }

    func testSaveSessionsUploadsWhenSyncEnabled() throws {
        preference.isEnabled = true
        let uploaded = expectation(description: "uploaded")
        cloud.onUpload = { uploaded.fulfill() }

        try store.saveSessions([TestData.session(day: 1)])

        wait(for: [uploaded], timeout: 2)
        XCTAssertEqual(cloud.uploadedBatches.count, 1)
    }

    func testSyncNowNoOpsWhenDisabled() async throws {
        preference.isEnabled = false
        let result = try await store.syncNow()
        XCTAssertNil(result)
        XCTAssertEqual(store.syncState, .idle)
    }

    func testDeletionDoesNotPropagateWhenSyncDisabled() throws {
        let kept = TestData.session(day: 1)
        let removed = TestData.session(day: 2)
        local.storedSessions = [kept, removed]
        preference.isEnabled = false

        let deletion = expectation(description: "should not delete remotely")
        deletion.isInverted = true
        cloud.onDelete = { deletion.fulfill() }
        try store.saveSessions([kept])
        wait(for: [deletion], timeout: 0.3)

        XCTAssertTrue(cloud.deletedIDBatches.isEmpty)
        XCTAssertEqual(local.storedSessions.map(\.id), [kept.id])
    }

    func testPurgeStillWorksWhenSyncDisabled() async throws {
        preference.isEnabled = false
        let ids: Set<UUID> = [UUID()]
        try await store.purgeCloudData(sessionIDs: ids)
        XCTAssertEqual(cloud.purgeCallCount, 1)
        XCTAssertEqual(cloud.lastPurgedSessionIDs, ids)
    }
}

@MainActor
final class ICloudSyncViewModelTests: XCTestCase {
    func testSyncNowGuardedByPreference() async {
        let store = InMemoryStore()
        store.isCloudSyncSupported = true
        store.isICloudSyncEnabled = false
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.syncNow()
        XCTAssertFalse(viewModel.isSyncing)
        XCTAssertNotEqual(viewModel.syncState, .syncing)
    }

    func testDisableICloudSyncCanPurgeRemote() async {
        let store = InMemoryStore()
        store.isCloudSyncSupported = true
        store.isICloudSyncEnabled = true
        let session = TestData.session(day: 3)
        store.storedSessions = [session]
        let viewModel = AppViewModel(store: store, locationManager: MockLocationReminderManager())

        viewModel.disableICloudSync(deleteRemoteData: true)

        XCTAssertFalse(viewModel.isICloudSyncEnabled)
        let deadline = Date().addingTimeInterval(2)
        while store.purgeCloudCallCount == 0, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(store.purgeCloudCallCount, 1)
        XCTAssertEqual(store.lastPurgedSessionIDs, [session.id])
    }
}
