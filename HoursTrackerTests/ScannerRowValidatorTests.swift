import XCTest
@testable import HoursTracker

final class ScannerRowValidatorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testAcceptsNormalDayShift() {
        let row = ScannerLLMRow(
            date: "12/07/2026",
            clockIn: "08:00",
            clockOut: "17:00",
            totalHours: 9,
            confidence: 0.9
        )
        guard case .accepted(let draft) = ScannerRowValidator.validate(row, calendar: calendar) else {
            return XCTFail("expected accepted")
        }
        XCTAssertFalse(draft.needsManualReview)
        XCTAssertEqual(draft.totalHours, 9, accuracy: 0.01)
        XCTAssertTrue(draft.isSelected)
    }

    func testEqualTimesNeedManualReviewNot24h() {
        let row = ScannerLLMRow(
            date: "12/07/2026",
            clockIn: "08:00",
            clockOut: "08:00",
            totalHours: 8,
            confidence: 0.5
        )
        guard case .needsReview(let draft) = ScannerRowValidator.validate(row, calendar: calendar) else {
            return XCTFail("expected needsReview for equal in/out")
        }
        XCTAssertTrue(draft.needsManualReview)
        XCTAssertLessThan(draft.totalHours, 1, "must not invent ~24h overnight")
        XCTAssertFalse(draft.isSelected)
    }

    func testHoursOver16NeedReview() {
        let row = ScannerLLMRow(
            date: "12/07/2026",
            clockIn: "06:00",
            clockOut: "23:00",
            confidence: 0.8
        )
        guard case .needsReview(let draft) = ScannerRowValidator.validate(row, calendar: calendar) else {
            return XCTFail("expected needsReview for >16h")
        }
        XCTAssertTrue(draft.needsManualReview)
        XCTAssertGreaterThan(draft.totalHours, 16)
    }

    func testRejectsUnparseableDate() {
        let row = ScannerLLMRow(
            date: "not-a-date",
            clockIn: "08:00",
            clockOut: "17:00"
        )
        guard case .rejected = ScannerRowValidator.validate(row, calendar: calendar) else {
            return XCTFail("expected rejected")
        }
    }

    func testValidateAllCounts() {
        let rows = [
            ScannerLLMRow(date: "12/07/2026", clockIn: "08:00", clockOut: "17:00"),
            ScannerLLMRow(date: "13/07/2026", clockIn: "09:00", clockOut: "09:00"),
            ScannerLLMRow(date: "bad", clockIn: "08:00", clockOut: "17:00")
        ]
        let (drafts, details) = ScannerRowValidator.validateAll(rows, calendar: calendar)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(details.acceptedCount, 1)
        XCTAssertEqual(details.reviewCount, 1)
        XCTAssertEqual(details.rejectedCount, 1)
    }
}

final class EqualTimeOvernightGuardTests: XCTestCase {
    func testParseEqualTimesDoesNotCreate24hShift() async {
        let text = "12/07/2026 08:00 08:00"
        let drafts = TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 1)
        let draft = drafts[0]
        XCTAssertTrue(draft.needsManualReview)
        XCTAssertLessThan(draft.totalHours, 1)
        XCTAssertFalse(
            ScannerRowValidator.isNear24HourSpan(draft.totalHours),
            "equal tokens must not become a ~24h overnight"
        )
    }

    func testNear24Helper() {
        XCTAssertTrue(ScannerRowValidator.isNear24HourSpan(24))
        XCTAssertTrue(ScannerRowValidator.isNear24HourSpan(23.75))
        XCTAssertFalse(ScannerRowValidator.isNear24HourSpan(9))
        XCTAssertFalse(ScannerRowValidator.isNear24HourSpan(16))
    }
}

/// Regression coverage for pasting this app's own CSV export (day name,
/// date, clock-in, clock-out, then several more numeric/currency columns)
/// into the free-text importer. Before `parseCSVColumnRows`, the trailing
/// pay-total column (e.g. "651.11") could be misread by the whole-line time
/// scanner as a bogus clock time.
final class CSVColumnPasteTests: XCTestCase {
    func testCSVRowWithTrailingPayTotalExtractsCorrectTimes() {
        let text = "יום ראשון,02.08.26,06:57,19:16,0.0,12.3,8.6,2.0,1.7,35.00 ₪,651.11 ₪"
        let drafts = TimesheetScannerManager.shared.parseSessions(from: text)

        XCTAssertEqual(drafts.count, 1)
        guard let draft = drafts.first else { return }
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: draft.clockIn), 6)
        XCTAssertEqual(calendar.component(.minute, from: draft.clockIn), 57)
        XCTAssertEqual(calendar.component(.hour, from: draft.clockOut), 19)
        XCTAssertEqual(calendar.component(.minute, from: draft.clockOut), 16)
    }

    func testMultiRowCSVExportIgnoresHeaderAndTotalsRows() {
        let text = """
        יום,תאריך,כניסה,יציאה,הפסקה,סה״כ,100%,125%,150%,נסיעות,שכר יומי
        יום ראשון,02.08.26,06:57,19:16,0.0,12.3,8.6,2.0,1.7,35.00 ₪,651.11 ₪
        יום שני,03.08.26,06:54,17:03,0.0,10.1,8.6,1.5,0.0,35.00 ₪,508.84 ₪
        סה״כ,,,,,250.4,189.2,41.4,19.8,770.00 ₪,"12,950.46 ₪"
        """
        let drafts = TimesheetScannerManager.shared.parseSessions(from: text)

        XCTAssertEqual(drafts.count, 2, "header and totals rows must not produce phantom sessions")
    }
}
