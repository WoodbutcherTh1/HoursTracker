import XCTest
@testable import HoursTracker

final class ExportTempFileStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExportTempFileStore.wipeAll()
    }

    override func tearDown() {
        ExportTempFileStore.wipeAll()
        super.tearDown()
    }

    func testWriteCreatesProtectedFileUnderExportsDirectory() throws {
        let writer = RecordingFileWriter()
        let url = try ExportTempFileStore.write(
            data: Data("report".utf8),
            fileName: "HoursReport-test.txt",
            writer: writer
        )

        XCTAssertTrue(url.path.contains("/Exports/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(writer.writingOptions.contains(.completeFileProtectionUnlessOpen))
        XCTAssertTrue(writer.writingOptions.contains(.atomic))
        if let protection = try ProtectedFileMigration.protection(at: url) {
            XCTAssertEqual(protection, .completeUnlessOpen)
        }
    }

    func testWipeAllRemovesExportFiles() throws {
        let url = try ExportTempFileStore.write(
            data: Data("temp".utf8),
            fileName: "HoursReport-wipe.txt"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        ExportTempFileStore.wipeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRemoveOnlyDeletesFilesInsideExportsDirectory() throws {
        let exportURL = try ExportTempFileStore.write(
            data: Data("a".utf8),
            fileName: "HoursReport-remove.txt"
        )
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).txt")
        try Data("keep".utf8).write(to: outside, options: .atomic)
        defer { try? FileManager.default.removeItem(at: outside) }

        ExportTempFileStore.remove(exportURL)
        ExportTempFileStore.remove(outside)

        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
