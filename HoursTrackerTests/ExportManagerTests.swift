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

    func testMarkdownExportUsesSelectedLanguage() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all,
            language: .english
        )

        let url = try manager.export(report: report, format: .markdown, language: .english)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("|"))
        XCTAssertTrue(contents.contains("Monthly Hours Report"))
        XCTAssertTrue(contents.contains("Payroll summary"))
        XCTAssertTrue(contents.contains("Hours breakdown"))
        XCTAssertTrue(contents.contains("Pay breakdown"))
        XCTAssertTrue(contents.contains("Column guide"))
        XCTAssertTrue(contents.contains("Daily details"))
        XCTAssertTrue(contents.contains("Day"))
        XCTAssertTrue(contents.contains("Travel"))
        XCTAssertTrue(contents.contains("Daily wage"))
        XCTAssertTrue(contents.contains("100%"))
        XCTAssertTrue(contents.contains("125%"))
        XCTAssertTrue(contents.contains("150%"))
        // No Hebrew characters in an English export.
        XCTAssertNil(contents.range(of: #"\p{Hebrew}"#, options: .regularExpression))
        XCTAssertEqual(url.pathExtension, "md")
    }

    func testArabicExportLanguage() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all,
            language: .arabic
        )

        let url = try manager.export(report: report, format: .markdown, language: .arabic)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("ملخص الرواتب"))
        XCTAssertTrue(contents.contains("توزيع الساعات"))
        XCTAssertTrue(contents.contains("تفاصيل الأيام"))
        XCTAssertTrue(contents.contains("اليوم"))
        XCTAssertTrue(contents.contains("مواصلات"))
        XCTAssertTrue(contents.contains("الأجر اليومي"))
        XCTAssertFalse(contents.contains("Travel"))
        XCTAssertFalse(contents.contains("Gross"))
        XCTAssertFalse(contents.contains("Daily wage"))
    }

    func testHebrewExportLanguage() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all,
            language: .hebrew
        )

        let url = try manager.export(report: report, format: .txt, language: .hebrew)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("דוח שעות חודשי"))
        XCTAssertTrue(contents.contains("סיכום שכר"))
        XCTAssertTrue(contents.contains("פילוח שעות"))
        XCTAssertTrue(contents.contains("פירוט ימים"))
        XCTAssertTrue(contents.contains("נסיעות"))
        XCTAssertTrue(contents.contains("שכר יומי"))
        XCTAssertTrue(contents.contains("הפסקה"))
        XCTAssertTrue(contents.contains("100%"))
        // No English payroll words mixed into Hebrew export.
        XCTAssertFalse(contents.contains("Travel"))
        XCTAssertFalse(contents.contains("Gross"))
        XCTAssertFalse(contents.contains("Daily wage"))
        XCTAssertFalse(contents.contains("Break"))
        XCTAssertFalse(contents.contains(" OT"))
    }

    func testTXTExportIncludesPayrollChartsAndLegend() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all,
            language: .english
        )

        let url = try manager.export(report: report, format: .txt, language: .english)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("Payroll summary"))
        XCTAssertTrue(contents.contains("Hours breakdown"))
        XCTAssertTrue(contents.contains("Pay breakdown"))
        XCTAssertTrue(contents.contains("█") || contents.contains("░"))
        XCTAssertTrue(contents.contains("Column guide"))
        let legendIndex = contents.range(of: "Column guide")!.lowerBound
        let tableIndex = contents.range(of: "Daily details")!.lowerBound
        XCTAssertLessThan(legendIndex, tableIndex)
    }

    func testDOCXExportIncludesPayrollSections() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all,
            language: .english
        )

        let url = try manager.export(report: report, format: .docx, language: .english)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "docx")
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)

        // iOS tests cannot spawn `/usr/bin/unzip` (`Process` is unavailable).
        // Read the DOCX ZIP entry with the same Compression-backed helper that wrote it.
        let xmlData = try ZipWriter.data(forEntry: "word/document.xml", inArchiveAt: url)
        let xml = String(decoding: xmlData, as: UTF8.self)
        XCTAssertTrue(xml.contains("Payroll summary"))
        XCTAssertTrue(xml.contains("Hours breakdown"))
        XCTAssertTrue(xml.contains("Column guide"))
        XCTAssertTrue(xml.contains("Daily details"))
    }

    func testPDFExportWritesFile() throws {
        let report = manager.buildReport(
            sessions: [TestData.session(day: 1)],
            settings: settings,
            range: .all,
            language: .english
        )

        let url = try manager.export(report: report, format: .pdf, language: .english)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "pdf")
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }

    func testExportLanguagePhoneResolvesToDeviceLanguage() {
        XCTAssertEqual(ExportLanguage.phone.resolvedLanguage, AppLocale.current)
        XCTAssertEqual(ExportLanguage.arabic.resolvedLocale.language.languageCode?.identifier, "ar")
        XCTAssertEqual(ExportLanguage.hebrew.resolvedLocale.language.languageCode?.identifier, "he")
        XCTAssertEqual(ExportLanguage.english.resolvedLocale.language.languageCode?.identifier, "en")
    }
}
