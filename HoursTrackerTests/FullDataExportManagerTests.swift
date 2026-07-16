import XCTest
@testable import HoursTracker

final class FullDataExportManagerTests: XCTestCase {
    private var manager: FullDataExportManager!
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        manager = FullDataExportManager()
        settings = TestData.settings()
        settings.workerFullName = "Ada Lovelace"
        settings.workplaceName = "Analytical Engines"
    }

    func testJSONRoundTripPreservesCountsAndFields() throws {
        let completed = TestData.session(day: 1, inHour: 8, outHour: 17)
        var withNotes = TestData.session(day: 2, inHour: 9, outHour: 18)
        withNotes.notes = "=SUM(A1)"
        let open = TestData.session(day: 3, outHour: nil)
        let sessions = [completed, withNotes, open]

        let log = [
            ActivityLogEntry(
                level: .info,
                category: "clock",
                message: "Clocked in",
                details: "manual"
            )
        ]

        let exportedAt = TestData.date(2026, 7, 16, 12, 0)
        let data = try manager.buildJSON(
            settings: settings,
            sessions: sessions,
            activityLog: log,
            appVersion: "1.0 (test)",
            exportedAt: exportedAt
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(FullDataExportDocument.self, from: data)

        XCTAssertEqual(document.appVersion, "1.0 (test)")
        XCTAssertEqual(document.sessions.count, 3)
        XCTAssertEqual(document.activityLog.count, 1)
        XCTAssertEqual(document.settings.workerFullName, "Ada Lovelace")
        XCTAssertEqual(document.settings.workplaceName, "Analytical Engines")
        XCTAssertEqual(document.sessions.filter(\.isOpen).count, 1)
        XCTAssertEqual(
            document.sessions.first(where: { $0.notes != nil })?.notes,
            "=SUM(A1)"
        )
        XCTAssertEqual(document.computedBreakdowns.count, 2)

        let completedIDs = Set(sessions.filter { !$0.isOpen }.map(\.id))
        XCTAssertEqual(Set(document.computedBreakdowns.map(\.sessionId)), completedIDs)
    }

    func testSessionsCSVRowCountMatchesSessionsPlusHeader() {
        let sessions = [
            TestData.session(day: 1),
            TestData.session(day: 2, outHour: nil),
            {
                var s = TestData.session(day: 3)
                s.notes = "Late delivery"
                return s
            }()
        ]

        let csv = manager.buildSessionsCSV(settings: settings, sessions: sessions)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, sessions.count + 1)
        XCTAssertTrue(csv.contains("Late delivery"))
        XCTAssertTrue(csv.contains("true") || csv.contains("false"))
    }

    func testCSVEscapesFormulaInjectionPrefix() {
        var session = TestData.session(day: 1)
        session.notes = "=cmd"
        let csv = manager.buildSessionsCSV(settings: settings, sessions: [session])
        XCTAssertTrue(csv.contains("'=cmd") || csv.contains("\"'=cmd\""))
    }

    func testCSVZipContainsExpectedEntries() throws {
        let sessions = [
            TestData.session(day: 1),
            TestData.session(day: 2, outHour: nil)
        ]
        let log = [
            ActivityLogEntry(level: .success, category: "export", message: "test", details: "json")
        ]

        let url = try manager.export(
            settings: settings,
            sessions: sessions,
            activityLog: log,
            format: .csvZip,
            language: .english,
            exportedAt: TestData.date(2026, 7, 16)
        )
        defer { ExportTempFileStore.remove(url) }

        XCTAssertEqual(url.lastPathComponent, "HoursTracker-Full-Export-2026-07-16.zip")

        let profile = try ZipWriter.data(forEntry: "profile_settings.csv", inArchiveAt: url)
        let work = try ZipWriter.data(forEntry: "work_sessions.csv", inArchiveAt: url)
        let activity = try ZipWriter.data(forEntry: "activity_log.csv", inArchiveAt: url)

        let profileText = String(decoding: profile, as: UTF8.self)
        let workText = String(decoding: work, as: UTF8.self)
        let activityText = String(decoding: activity, as: UTF8.self)

        XCTAssertTrue(profileText.contains("workerFullName"))
        XCTAssertTrue(profileText.contains("Ada Lovelace"))

        let workLines = workText.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(workLines.count, sessions.count + 1)

        XCTAssertTrue(activityText.contains("export"))
        XCTAssertTrue(activityText.contains("test"))
    }

    func testJSONExportFileNameAndDecodable() throws {
        let url = try manager.export(
            settings: settings,
            sessions: [TestData.session(day: 5)],
            activityLog: [],
            format: .json,
            language: .english,
            exportedAt: TestData.date(2026, 7, 16)
        )
        defer { ExportTempFileStore.remove(url) }

        XCTAssertEqual(url.lastPathComponent, "HoursTracker-Full-Export-2026-07-16.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(FullDataExportDocument.self, from: data)
        XCTAssertEqual(document.sessions.count, 1)
    }

    func testPDFExportProducesNonEmptyFile() throws {
        let sessions = [
            TestData.session(day: 1),
            {
                var s = TestData.session(day: 2)
                s.notes = "Notes here"
                return s
            }(),
            TestData.session(day: 3, outHour: nil)
        ]
        let url = try manager.export(
            settings: settings,
            sessions: sessions,
            activityLog: [],
            format: .pdf,
            language: .hebrew,
            exportedAt: TestData.date(2026, 7, 16)
        )
        defer { ExportTempFileStore.remove(url) }

        XCTAssertEqual(url.pathExtension, "pdf")
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }
}
