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
        let sessions = [
            makeSession(hours: 8.6),
            makeSession(hours: 10.0)
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

    private func makeSession(hours: Double) -> WorkSession {
        let start = Date()
        let end = start.addingTimeInterval(hours * 3600)
        return WorkSession(
            date: start,
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
        13.07
        09:00
        18:00
        """
        let drafts = await TimesheetScannerManager.shared.parseSessions(from: text)
        XCTAssertGreaterThanOrEqual(drafts.count, 2)
    }

    func testFallbackWhenNoSessions() async throws {
        let result = await TimesheetScannerManager.shared.parseResult(from: "hello world nothing useful")
        XCTAssertTrue(result.usedManualFallback)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertTrue(result.drafts[0].needsManualReview)
    }
}
