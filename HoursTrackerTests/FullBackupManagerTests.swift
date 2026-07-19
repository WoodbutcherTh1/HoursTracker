import XCTest
@testable import HoursTracker
import HoursTrackerKit

final class FullBackupManagerTests: XCTestCase {
    private var tempDir: URL!
    private var manager: FullBackupManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ht-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = FullBackupManager()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTripLosslessSessionsAndSettings() throws {
        var settings = TestData.settings()
        settings.workerFullName = "Test Worker"
        settings.workerIDNumber = "123456782"
        settings.workplaceName = "Site A"
        settings.contractorName = "Contractor"

        let sessions = [
            TestData.session(day: 1, inHour: 8, outHour: 17),
            TestData.session(day: 2, inHour: 9, outHour: 18),
            TestData.session(day: 3, outHour: nil)
        ]
        let log = [
            ActivityLogEntry(level: .info, category: "clock", message: "Clocked in", details: "manual")
        ]

        let doc = manager.makeDocument(
            settings: settings,
            sessions: sessions,
            activityLog: log,
            exportedAt: TestData.date(2026, 7, 19, 18, 0),
            appVersion: "1.0 (test)"
        )
        XCTAssertEqual(doc.formatID, FullBackupDocument.formatID)
        XCTAssertEqual(doc.sessionCount, 3)
        XCTAssertEqual(doc.monthCount, 1)

        let data = try manager.encode(doc)
        let decoded = try manager.decode(from: data)

        XCTAssertEqual(decoded.settings.workerFullName, "Test Worker")
        XCTAssertEqual(decoded.settings.workerIDNumber, "123456782")
        XCTAssertEqual(decoded.settings.workplaceName, "Site A")
        XCTAssertEqual(decoded.settings.contractorName, "Contractor")
        XCTAssertEqual(decoded.sessions.count, 3)
        XCTAssertEqual(Set(decoded.sessions.map(\.id)), Set(sessions.map(\.id)))
        XCTAssertEqual(decoded.activityLog.count, 1)
    }

    func testRejectsGarbageFile() {
        let data = Data("not-a-backup".utf8)
        XCTAssertThrowsError(try manager.decode(from: data)) { error in
            XCTAssertTrue(error is FullBackupError)
        }
    }

    func testAcceptsLegacyFullDataExportJSON() throws {
        var settings = TestData.settings()
        settings.workerFullName = "Legacy"
        let exporter = FullDataExportManager()
        let data = try exporter.buildJSON(
            settings: settings,
            sessions: [TestData.session(day: 5)],
            activityLog: [],
            appVersion: "1.0",
            exportedAt: TestData.date(2026, 7, 1)
        )
        let decoded = try manager.decode(from: data)
        XCTAssertEqual(decoded.settings.workerFullName, "Legacy")
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.formatID, FullBackupDocument.formatID)
    }

    func testMergeSessionsByID() {
        let a = TestData.session(day: 1)
        var b = TestData.session(day: 2)
        let sharedID = a.id
        var updated = a
        updated.notes = "from-backup"

        var byID = Dictionary(uniqueKeysWithValues: [a, b].map { ($0.id, $0) })
        byID[sharedID] = updated
        let merged = Array(byID.values)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.id == sharedID })?.notes, "from-backup")
    }
}
