import XCTest
@testable import HoursTracker

final class SessionTombstoneStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SessionTombstoneStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TombstoneTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = SessionTombstoneStore(documentsDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        try super.tearDownWithError()
    }

    func testRecordPersistsAcrossReload() {
        let id = UUID()
        store.record(ids: [id])

        let reloaded = SessionTombstoneStore(documentsDirectory: directory)
        XCTAssertEqual(reloaded.tombstoneIDs, [id])
    }

    func testPruneRemovesOldTombstones() {
        let oldID = UUID()
        let freshID = UUID()
        store.record(ids: [oldID], at: Date().addingTimeInterval(-100_000_000))
        store.record(ids: [freshID], at: Date())

        store.prune(olderThan: 1_000)

        XCTAssertEqual(store.tombstoneIDs, [freshID])
    }
}
