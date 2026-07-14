import XCTest
@testable import HoursTracker

final class ExportManagerTests: XCTestCase {
    private var manager: ExportManager!
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        manager = ExportManager()
        settings = TestData.settings()
    }

    func testReportExcludesOpenSessions() {
        let completed = TestData.session(day: 1)
        let open = TestData.session(day: 2, outHour: nil)

        let report = manager.buildReport(sessions: [completed, open], settings: settings, range: .all)

        XCTAssertEqual(report.rows.count, 1)
        XCTAssertEqual(report.rows.first?.session.id, completed.id)
    }

    func testMonthRangeFiltersOtherMonths() {
        let january = TestData.session(month: 1, day: 15)
        let february = TestData.session(month: 2, day: 15)
        let januaryNextYear = TestData.session(year: 2027, month: 1, day: 15)

        let report = manager.buildReport(
            sessions: [january, february, januaryNextYear],
            settings: settings,
            range: .month(year: 2026, month: 1)
        )

        XCTAssertEqual(report.rows.count, 1)
        XCTAssertEqual(report.rows.first?.session.id, january.id)
    }

    func testCustomRangeIncludesBothEndpoints() {
        let before = TestData.session(day: 9)
        let start = TestData.session(day: 10)
        let middle = TestData.session(day: 12)
        let end = TestData.session(day: 15)
        let after = TestData.session(day: 16)

        let report = manager.buildReport(
            sessions: [before, start, middle, end, after],
            settings: settings,
            range: .custom(from: TestData.date(2026, 1, 10), to: TestData.date(2026, 1, 15))
        )

        let ids = Set(report.rows.map(\.session.id))
        XCTAssertEqual(ids, [start.id, middle.id, end.id])
    }

    func testCustomRangeBoundsIgnoreTimeOfDay() {
        let session = TestData.session(day: 10)

        let report = manager.buildReport(
            sessions: [session],
            settings: settings,
            range: .custom(
                from: TestData.date(2026, 1, 10, 23, 59),
                to: TestData.date(2026, 1, 10, 0, 1)
            )
        )

        XCTAssertEqual(report.rows.count, 1)
    }

    func testTotalsSumPerDayBreakdowns() {
        // 8h regular day + 12h day (8.6 regular, 2 at 125%, 1.4 at 150%)
        let regularDay = TestData.session(day: 1, inHour: 8, outHour: 16)
        let longDay = TestData.session(day: 2, inHour: 6, outHour: 18)

        let report = manager.buildReport(sessions: [regularDay, longDay], settings: settings, range: .all)

        XCTAssertEqual(report.totals.totalHours, 20.0, accuracy: 0.001)
        XCTAssertEqual(report.totals.regularHours, 16.6, accuracy: 0.001)
        XCTAssertEqual(report.totals.ot125Hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(report.totals.ot150Hours, 1.4, accuracy: 0.001)
        // (800 + 35) + (860 + 250 + 210 + 35)
        XCTAssertEqual(report.totals.totalPay, 2190, accuracy: 0.01)
    }

    func testMarkdownExportWritesFile() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all
        )

        let url = try manager.export(report: report, format: .markdown)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("|"))
        XCTAssertTrue(contents.contains(L10n.reportLegendTitle))
        XCTAssertTrue(contents.contains(L10n.reportLegendGross))
        XCTAssertEqual(url.pathExtension, "md")
    }

    func testTXTExportIncludesColumnLegend() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all
        )

        let url = try manager.export(report: report, format: .txt)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains(L10n.reportLegendTitle))
        XCTAssertTrue(contents.contains(L10n.reportLegendDate))
        XCTAssertTrue(contents.contains(L10n.reportLegendIn))
        XCTAssertTrue(contents.contains(L10n.reportLegendOut))
        XCTAssertTrue(contents.contains(L10n.reportLegendGross))
        XCTAssertTrue(contents.contains(L10n.reportLegendNet))
        // Legend appears before the table header row.
        let legendIndex = contents.range(of: L10n.reportLegendTitle)!.lowerBound
        let tableIndex = contents.range(of: L10n.reportColDate)!.lowerBound
        XCTAssertLessThan(legendIndex, tableIndex)
    }

    func testDOCXExportIncludesColumnLegend() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all
        )

        let url = try manager.export(report: report, format: .docx)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        // DOCX is a zip; document.xml contains the legend text as plain XML text nodes.
        XCTAssertEqual(url.pathExtension, "docx")
        XCTAssertFalse(data.isEmpty)

        // Smoke-check via markdown path already covers legend strings; here verify
        // the Word package embeds the legend title in document.xml.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-legend-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Unzip with unzip CLI when available.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", url.path, "-d", tmp.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let xml = try String(
            contentsOf: tmp.appendingPathComponent("word/document.xml"),
            encoding: .utf8
        )
        XCTAssertTrue(xml.contains(L10n.reportLegendTitle))
        XCTAssertTrue(xml.contains(L10n.reportLegendGross))
    }

    func testPDFExportWritesFile() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all
        )

        let url = try manager.export(report: report, format: .pdf)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "pdf")
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
        // PDF magic header
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }
}
