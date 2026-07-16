import XCTest
@testable import HoursTracker

final class CorruptFileQuarantineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorruptQuarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testQuarantineMovesFileToCorruptSibling() throws {
        let url = directory.appendingPathComponent("work_sessions.json")
        try Data("not-json".utf8).write(to: url, options: .atomic)

        let quarantined = try XCTUnwrap(
            CorruptFileQuarantine.quarantine(at: url, fileManager: .default)
        )

        XCTAssertEqual(quarantined.lastPathComponent, "work_sessions.json.corrupt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantined.path))
        XCTAssertEqual(try String(contentsOf: quarantined, encoding: .utf8), "not-json")
    }

    func testPersistenceLoadQuarantinesCorruptSessions() throws {
        let sessionsURL = directory.appendingPathComponent("work_sessions.json")
        try Data("{broken".utf8).write(to: sessionsURL, options: .atomic)

        let store = PersistenceManager(
            fileWriter: RecordingFileWriter(),
            documentsDirectory: directory
        )
        let loaded = store.loadSessions()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionsURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionsURL.appendingPathExtension("corrupt").path
            )
        )
    }

    func testRemoveSidecarsDeletesQuarantineFiles() throws {
        let url = directory.appendingPathComponent("workplace_settings.json")
        let corrupt = url.appendingPathExtension("corrupt")
        try Data("{}".utf8).write(to: corrupt, options: .atomic)

        CorruptFileQuarantine.removeSidecars(for: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
    }
}
