import XCTest
@testable import HoursTracker

@MainActor
final class ActivityLogStoreTests: XCTestCase {
    private var store: ActivityLogStore!

    override func setUp() {
        super.setUp()
        store = ActivityLogStore.shared
        store.wipeForPrivacy()
    }

    override func tearDown() {
        store.wipeForPrivacy()
        store = nil
        super.tearDown()
    }

    func testExportFormatsProduceNonEmptyFiles() throws {
        store.log("Clocked in", level: .success, category: "clock", details: "test")
        store.log("Settings saved", level: .info, category: "settings")

        for format in ActivityLogExportFormat.allCases {
            let url = try store.export(format: format)
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty, "\(format) export should not be empty")
            XCTAssertEqual(url.pathExtension, format.fileExtension)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCSVContainsHeaderAndMessage() throws {
        store.wipeForPrivacy()
        store.log("Manual shift added", level: .success, category: "session", details: "note")

        let url = try store.export(format: .csv)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("timestamp,level,category,message,details"))
        XCTAssertTrue(text.contains("Manual shift added"))
        XCTAssertTrue(text.contains("session"))
    }

    func testWipeRemovesEntries() {
        store.log("temp", level: .info, category: "system")
        XCTAssertFalse(store.entries.isEmpty)
        store.wipeForPrivacy()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testScrubRemovesCoordinateDetailsFromLocationEntries() {
        let polluted = ActivityLogEntry(
            level: .success,
            category: "location",
            message: "Workplace location set",
            details: "32.08530, 34.78180"
        )
        let clean = ActivityLogEntry(
            level: .info,
            category: "location",
            message: "Arrival reminders enabled",
            details: nil
        )
        let unrelated = ActivityLogEntry(
            level: .success,
            category: "clock",
            message: "Clocked in",
            details: "2026-07-16T08:00:00Z"
        )
        store.replaceEntriesForTesting([polluted, clean, unrelated])

        store.scrubCoordinateDetailsIfNeeded()

        XCTAssertNil(store.entries.first { $0.id == polluted.id }?.details)
        XCTAssertNil(store.entries.first { $0.id == clean.id }?.details)
        XCTAssertEqual(store.entries.first { $0.id == unrelated.id }?.details, "2026-07-16T08:00:00Z")
    }

    func testExportWritesIntoExportsTempDirectory() throws {
        store.log("Clocked in", level: .success, category: "clock")
        let url = try store.export(format: .txt)
        defer { ExportTempFileStore.remove(url) }
        XCTAssertTrue(url.path.contains("/Exports/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        if let protection = try ProtectedFileMigration.protection(at: url) {
            XCTAssertEqual(protection, .completeUnlessOpen)
        }
    }
}
