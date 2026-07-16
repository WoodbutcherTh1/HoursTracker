import XCTest
@testable import HoursTracker

final class ProtectedFileWriterTests: XCTestCase {
    func testWritingOptionsIncludeAtomicAndCompleteUnlessOpen() {
        let options = ProtectedFileWriter.writingOptions
        XCTAssertTrue(options.contains(.atomic))
        XCTAssertTrue(options.contains(.completeFileProtectionUnlessOpen))
    }

    func testWriterUsesProtectedOptionsAndCreatesFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProtectedFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("sample.json")
        let writer = RecordingFileWriter()
        try writer.write(Data(#"{"ok":true}"#.utf8), to: url)

        XCTAssertEqual(writer.urls, [url])
        XCTAssertTrue(writer.writingOptions.contains(.atomic))
        XCTAssertTrue(writer.writingOptions.contains(.completeFileProtectionUnlessOpen))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Simulator often does not persist NSFileProtectionCompleteUnlessOpen on tmp;
        // assert the attribute only when the runtime reports a non-nil class.
        if let protection = try ProtectedFileMigration.protection(at: url) {
            XCTAssertEqual(protection, .completeUnlessOpen)
        }
    }

    func testMigrationRewritesWhenProtectionIsMissingOrWrong() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProtectedFileMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("legacy.json")
        // Force a non-matching protection class so migration must rewrite.
        try Data(#"{"legacy":true}"#.utf8).write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )

        let writer = RecordingFileWriter()
        try ProtectedFileMigration.ensureProtection(at: url, writer: writer)

        XCTAssertEqual(writer.urls, [url], "migration should rewrite files that are not completeUnlessOpen")
        XCTAssertTrue(writer.writingOptions.contains(.completeFileProtectionUnlessOpen))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
