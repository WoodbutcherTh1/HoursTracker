import XCTest
@testable import HoursTracker

final class FullDataImportTests: XCTestCase {
    func testRoundTripJSONImport() throws {
        let exporter = FullDataExportManager()
        var settings = TestData.settings()
        settings.workerFullName = "Import Worker"
        let sessions = [TestData.session(day: 3), TestData.session(day: 4)]
        let data = try exporter.buildJSON(
            settings: settings,
            sessions: sessions,
            activityLog: [],
            appVersion: "1.0-test",
            exportedAt: TestData.date(2026, 7, 22)
        )
        let decoded = try exporter.decodeJSONDocument(from: data)
        XCTAssertEqual(decoded.settings.workerFullName, "Import Worker")
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.appVersion, "1.0-test")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(
            try FullDataExportManager().decodeJSONDocument(from: Data("nope".utf8))
        )
    }
}
