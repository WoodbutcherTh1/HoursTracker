import XCTest
@testable import HoursTracker

final class WorkerIDKeychainPersistenceTests: XCTestCase {
    private var directory: URL!
    private var writer: RecordingFileWriter!
    private var store: PersistenceManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkerIDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writer = RecordingFileWriter()
        store = PersistenceManager(
            fileWriter: writer,
            documentsDirectory: directory
        )
        try KeychainStore.delete(.workerIDNumber)
    }

    override func tearDownWithError() throws {
        try KeychainStore.delete(.workerIDNumber)
        try? FileManager.default.removeItem(at: directory)
        store = nil
        writer = nil
        directory = nil
        try super.tearDownWithError()
    }

    func testSaveKeepsIDInMemoryAPIButOmitsFromJSON() throws {
        var settings = TestData.settings()
        settings.workerIDNumber = "123456789"

        try store.saveSettings(settings)

        let diskData = try Data(contentsOf: store.settingsURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: diskData) as? [String: Any])
        XCTAssertEqual(object["workerIDNumber"] as? String, "")
        XCTAssertFalse(String(data: diskData, encoding: .utf8)?.contains("123456789") == true)

        let loaded = store.loadSettings()
        XCTAssertEqual(loaded.workerIDNumber, "123456789")
        XCTAssertEqual(KeychainStore.string(for: .workerIDNumber), "123456789")
    }

    func testMigratesPlaintextIDFromExistingJSON() throws {
        var legacy = TestData.settings()
        legacy.workerIDNumber = "987654321"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)
        try FileManager.default.createDirectory(
            at: store.settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: store.settingsURL, options: .atomic)

        let loaded = store.loadSettings()
        XCTAssertEqual(loaded.workerIDNumber, "987654321")

        let diskData = try Data(contentsOf: store.settingsURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: diskData) as? [String: Any])
        XCTAssertEqual(object["workerIDNumber"] as? String, "")
        XCTAssertEqual(KeychainStore.string(for: .workerIDNumber), "987654321")
    }

    func testEmptyIDClearsKeychain() throws {
        try KeychainStore.setString("111222333", for: .workerIDNumber)
        var settings = TestData.settings()
        settings.workerIDNumber = ""

        try store.saveSettings(settings)

        XCTAssertNil(KeychainStore.string(for: .workerIDNumber))
        XCTAssertEqual(store.loadSettings().workerIDNumber, "")
    }

    func testMergeSettingsNeverTakesRemoteNationalID() {
        var local = TestData.settings()
        local.workerIDNumber = "local-id"
        local.modifiedAt = Date(timeIntervalSince1970: 1)

        var remote = TestData.settings()
        remote.workerIDNumber = "remote-id"
        remote.workplaceName = "Remote Workplace"
        remote.modifiedAt = Date(timeIntervalSince1970: 100)

        let merged = CloudKitSyncManager.mergeSettings(local: local, remote: remote)
        XCTAssertEqual(merged.workplaceName, "Remote Workplace")
        XCTAssertEqual(merged.workerIDNumber, "local-id")
    }

    func testSavingDefaultSettingsClearsKeychainItem() throws {
        try KeychainStore.setString("555666777", for: .workerIDNumber)
        try store.saveSettings(.default)
        XCTAssertNil(KeychainStore.string(for: .workerIDNumber))
    }
}
