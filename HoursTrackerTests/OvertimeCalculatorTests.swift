import XCTest
@testable import HoursTracker

final class OvertimeCalculatorTests: XCTestCase {
    private var settings: WorkplaceSettings!

    override func setUp() {
        super.setUp()
        settings = WorkplaceSettings(
            workplaceName: "Test",
            contractorName: nil,
            workerFullName: "Worker",
            workerIDNumber: "123",
            employeeNumber: "456",
            hourlyRate: 100,
            dailyGasAllowance: 35,
            standardDayHours: 8.6,
            ot125HoursCap: 2.0,
            locationLatitude: nil,
            locationLongitude: nil,
            locationRadiusMeters: 150,
            maritalStatus: .single,
            hasChildren: false,
            numberOfChildren: 0,
            spouseEmployed: false,
            modifiedAt: Date()
        )
    }

    func testRegularHoursOnly() {
        let result = OvertimeCalculator.breakdown(totalHours: 8.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.0, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 835, accuracy: 0.01) // 800 + 35 gas
        XCTAssertLessThan(result.netPay, result.grossPay)
        XCTAssertGreaterThan(result.netPay, 0)
    }

    func testExactlyStandardDayHours() {
        let result = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 895, accuracy: 0.01) // 860 + 35
    }

    func testOT125Only() {
        let result = OvertimeCalculator.breakdown(totalHours: 10.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 0, accuracy: 0.001)
        // 860 + 1.4*125 + 35 = 1070
        XCTAssertEqual(result.totalPay, 1070, accuracy: 0.01)
    }

    func testOT125CapAndOT150() {
        let result = OvertimeCalculator.breakdown(totalHours: 12.0, settings: settings)
        XCTAssertEqual(result.regularHours, 8.6, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.ot150Hours, 1.4, accuracy: 0.001)
        // 860 + 250 + 210 + 35 = 1355
        XCTAssertEqual(result.totalPay, 1355, accuracy: 0.01)
    }

    func testZeroHours() {
        let result = OvertimeCalculator.breakdown(totalHours: 0, settings: settings)
        XCTAssertEqual(result.regularHours, 0, accuracy: 0.001)
        XCTAssertEqual(result.totalPay, 35, accuracy: 0.01)
    }

    func testAggregateMultipleSessions() {
        // Distinct days: overtime and the gas allowance are per calendar day,
        // so each day gets its own standard-hours allowance and gas payment.
        let sessions = [
            makeSession(hours: 8.6, daysAgo: 1),
            makeSession(hours: 10.0, daysAgo: 0)
        ]
        let result = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
        XCTAssertEqual(result.regularHours, 17.2, accuracy: 0.001)
        XCTAssertEqual(result.ot125Hours, 1.4, accuracy: 0.001)
        XCTAssertEqual(result.gasAllowance, 70, accuracy: 0.01)
        XCTAssertEqual(result.grossPay, result.totalPay, accuracy: 0.01)
        XCTAssertLessThan(result.netPay, result.grossPay)
    }

    func testCreditPointsBaseResident() {
        XCTAssertEqual(TaxCreditPointsCalculator.creditPoints(for: settings), 2.25, accuracy: 0.001)
    }

    func testCreditPointsWithChildrenAndUnemployedSpouse() {
        settings.maritalStatus = .married
        settings.spouseEmployed = false
        settings.hasChildren = true
        settings.numberOfChildren = 2
        // 2.25 + 2 children + 0.5 spouse = 4.75
        XCTAssertEqual(TaxCreditPointsCalculator.creditPoints(for: settings), 4.75, accuracy: 0.001)
        let withKids = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        settings.numberOfChildren = 0
        settings.hasChildren = false
        settings.spouseEmployed = true
        let without = OvertimeCalculator.breakdown(totalHours: 8.6, settings: settings)
        XCTAssertGreaterThanOrEqual(withKids.netPay, without.netPay)
    }

    private func makeSession(hours: Double, daysAgo: Int = 0) -> WorkSession {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!)
        let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
        let end = start.addingTimeInterval(hours * 3600)
        return WorkSession(
            date: day,
            clockIn: start,
            clockOut: end,
            isManualEntry: false
        )
    }
}

final class PayrollPeriodTests: XCTestCase {
    func testCalendarMonthWhenStartDayIsOne() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 15
        let date = Calendar.current.date(from: comps)!
        let period = HistoryPeriodHelper.payrollPeriod(containing: date, startDay: 1)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 1)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 7)
        XCTAssertEqual(Calendar.current.component(.day, from: period.end), 31)
        XCTAssertEqual(Calendar.current.component(.month, from: period.end), 7)
    }

    func testCustomStartDaySpansMonths() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 15
        let date = Calendar.current.date(from: comps)!
        let period = HistoryPeriodHelper.payrollPeriod(containing: date, startDay: 10)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 10)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 7)
        XCTAssertEqual(Calendar.current.component(.day, from: period.end), 9)
        XCTAssertEqual(Calendar.current.component(.month, from: period.end), 8)
        XCTAssertTrue(period.contains(date))
    }

    func testDateBeforeStartBelongsToPreviousCycle() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 5
        let date = Calendar.current.date(from: comps)!
        let period = HistoryPeriodHelper.payrollPeriod(containing: date, startDay: 10)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 6)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 10)
        XCTAssertEqual(Calendar.current.component(.month, from: period.end), 7)
        XCTAssertEqual(Calendar.current.component(.day, from: period.end), 9)
    }
}

final class TimesheetScannerParserTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func assertDayMonthYear(
        _ date: Date,
        _ day: Int,
        _ month: Int,
        _ year: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        XCTAssertEqual(c.day, day, file: file, line: line)
        XCTAssertEqual(c.month, month, file: file, line: line)
        XCTAssertEqual(c.year, year, file: file, line: line)
    }

    private func assertHourMinute(
        _ date: Date,
        _ hour: Int,
        _ minute: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        XCTAssertEqual(c.hour, hour, file: file, line: line)
        XCTAssertEqual(c.minute, minute, file: file, line: line)
    }

    func testParseLineOrientedTimesheet() async throws {
        let text = """
        Date In Out
        12/07/2026 08:00 17:00
        13/07/2026 07:30 16:45
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].totalHours, 9.0, accuracy: 0.01)
        XCTAssertTrue(drafts[0].isSelected)
    }

    func testParseHebrewKeywordsLine() async throws {
        let text = "תאריך 01/07/2026 כניסה 08:15 יציאה 17:00"
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].totalHours, 8.75, accuracy: 0.01)
    }

    func testGlobalPairingAcrossSplitLines() async throws {
        let text = """
        12.07.2026
        08:00
        17:30
        13/07
        09:00
        18:00
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertGreaterThanOrEqual(drafts.count, 2)
    }

    func testDottedClockTimesAreNotParsedAsDates() async throws {
        // Real Israeli printed sheet: slash dates + dotted clock times (7.17 / 17.08).
        // OCR also emits cells out of order (RTL: out, in, then date).
        let text = """
        תאריך יום כניסה יציאה
        17.08
        7.17
        01/07/2024
        17.04
        7.05
        02/07/2024
        17.04
        7.30
        05/07/2024
        17.42
        7.13
        06/07/2024
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 4)

        assertDayMonthYear(drafts[0].date, 1, 7, 2024)
        assertHourMinute(drafts[0].clockIn, 7, 17)
        assertHourMinute(drafts[0].clockOut, 17, 8)

        assertDayMonthYear(drafts[1].date, 2, 7, 2024)
        assertHourMinute(drafts[1].clockIn, 7, 5)
        assertHourMinute(drafts[1].clockOut, 17, 4)

        assertDayMonthYear(drafts[2].date, 5, 7, 2024)
        assertHourMinute(drafts[2].clockIn, 7, 30)
        assertHourMinute(drafts[2].clockOut, 17, 4)

        assertDayMonthYear(drafts[3].date, 6, 7, 2024)
        assertHourMinute(drafts[3].clockIn, 7, 13)
        assertHourMinute(drafts[3].clockOut, 17, 42)

        // Must not invent May/August days from 7.05 / 17.08.
        let months = Set(drafts.map { calendar.component(.month, from: $0.date) })
        XCTAssertEqual(months, [7])
    }

    func testYearlessDottedTokenIsNotADateWhenYearBearingDatesExist() async throws {
        let text = """
        7.05
        17.08
        01/07/2024
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 1)
        assertDayMonthYear(drafts[0].date, 1, 7, 2024)
        assertHourMinute(drafts[0].clockIn, 7, 5)
        assertHourMinute(drafts[0].clockOut, 17, 8)
    }

    func testDottedHeaderDateDoesNotStealRowTimes() async throws {
        let text = """
        Ameen Ab
        15.7.2024
        17.08
        7.17
        01/07/2024
        17.04
        7.05
        02/07/2024
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 2)
        assertDayMonthYear(drafts[0].date, 1, 7, 2024)
        assertHourMinute(drafts[0].clockIn, 7, 17)
        assertHourMinute(drafts[0].clockOut, 17, 8)
        assertDayMonthYear(drafts[1].date, 2, 7, 2024)
        // Header 15.7.2024 must not appear as a work day.
        XCTAssertFalse(drafts.contains {
            calendar.component(.day, from: $0.date) == 15
                && calendar.component(.month, from: $0.date) == 7
        })
    }

    func testEnglishMonthDayTableIgnoresTotalHoursDecimals() async throws {
        // US-style export: MM-DD dates, colon clock times, dotted total_hours (9.85).
        let text = """
        date day entry exit total_hours
        07-01 Wed 07:17 17:08 9.85
        07-02 Thu 07:05 17:04 9.98
        07-05 Sun 07:30 17:04 9.57
        07-06 Mon 07:15 17:42 10.45
        07-07 Tue 07:26 17:02 9.60
        07-09 Thu 07:27 17:06 9.65
        07-13 Mon 07:23 17:01 9.63
        07-14 Tue 07:20 16:33 9.22
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 8)

        let year = calendar.component(.year, from: Date())
        assertDayMonthYear(drafts[0].date, 1, 7, year)
        assertHourMinute(drafts[0].clockIn, 7, 17)
        assertHourMinute(drafts[0].clockOut, 17, 8)
        XCTAssertEqual(drafts[0].totalHours, 9.85, accuracy: 0.02)

        assertDayMonthYear(drafts[3].date, 6, 7, year)
        assertHourMinute(drafts[3].clockIn, 7, 15)
        assertHourMinute(drafts[3].clockOut, 17, 42)

        assertDayMonthYear(drafts[5].date, 9, 7, year)
        assertDayMonthYear(drafts[7].date, 14, 7, year)
        assertHourMinute(drafts[7].clockIn, 7, 20)
        assertHourMinute(drafts[7].clockOut, 16, 33)

        // total_hours like 10.45 must not become a fake 10:45 clock-in.
        XCTAssertFalse(drafts.contains {
            calendar.component(.hour, from: $0.clockIn) == 10
                && calendar.component(.minute, from: $0.clockIn) == 45
        })
    }

    func testPicksMorningAndEveningWhenExtraDecimalOnRow() async throws {
        // Dotted Hebrew clocks + a total-hours-like 9.50 on the same reconstructed row.
        let text = "01/07/2024 7.17 17.08 9.50"
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertEqual(drafts.count, 1)
        assertDayMonthYear(drafts[0].date, 1, 7, 2024)
        assertHourMinute(drafts[0].clockIn, 7, 17)
        assertHourMinute(drafts[0].clockOut, 17, 8)
        XCTAssertEqual(drafts[0].totalHours, 9.85, accuracy: 0.02)
    }

    func testRejectsAbsurdShiftDurations() async throws {
        let text = "01/07/2024 00:05 23:55"
        let result = await TimesheetScannerManager.shared.parseResult(from: text)
        // ~23.8h is rejected by finalize → manual fallback draft.
        XCTAssertTrue(result.usedManualFallback)
        XCTAssertTrue(result.drafts[0].needsManualReview)
    }

    func testFallbackWhenNoSessions() async throws {
        let result = await TimesheetScannerManager.shared.parseResult(from: "hello world nothing useful")
        XCTAssertTrue(result.usedManualFallback)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertTrue(result.drafts[0].needsManualReview)
    }
}
