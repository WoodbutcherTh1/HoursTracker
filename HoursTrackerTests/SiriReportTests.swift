import XCTest
@testable import HoursTracker

@MainActor
final class SiriReportTests: XCTestCase {
    private let now = TestData.date(2026, 1, 15, 12)

    private func report(_ sessions: [WorkSession]) -> SiriReport {
        SiriReport(sessions: sessions, settings: TestData.settings(), now: now)
    }

    func testTodayCountsOnlyFinishedShiftsFromToday() {
        let sessions = [
            TestData.session(day: 15, inHour: 8, outHour: 12),
            TestData.session(day: 14, inHour: 8, outHour: 16),
            TestData.session(day: 15, inHour: 13, outHour: nil)
        ]
        let totals = report(sessions).totals(for: .today)
        XCTAssertEqual(totals.shifts, 1)
        XCTAssertEqual(totals.hours, 4, accuracy: 0.001)
        XCTAssertNotNil(totals.breakdown)
    }

    func testLastMonthUsesThePreviousCalendarMonth() {
        let sessions = [
            TestData.session(year: 2025, month: 12, day: 30, inHour: 8, outHour: 16),
            TestData.session(day: 2, inHour: 8, outHour: 16)
        ]
        let totals = report(sessions).totals(for: .lastMonth)
        XCTAssertEqual(totals.shifts, 1)
        XCTAssertEqual(totals.hours, 8, accuracy: 0.001)
    }

    func testEmptyPeriodHasNoBreakdown() {
        let totals = report([]).totals(for: .thisWeek)
        XCTAssertEqual(totals.shifts, 0)
        XCTAssertNil(totals.breakdown)
    }

    func testPayIsLeftOutWhenHidden() throws {
        let totals = report([TestData.session(day: 15, inHour: 8, outHour: 12)]).totals(for: .today)
        let breakdown = try XCTUnwrap(totals.breakdown)
        XCTAssertNil(SiriReport.payText(breakdown, showsNet: false, hidden: true))
        XCTAssertNotNil(SiriReport.payText(breakdown, showsNet: false, hidden: false))
    }

    func testClockFormatsHoursAndMinutes() {
        XCTAssertEqual(SiriReport.clock(hours: 6.72), "6:43")
        XCTAssertEqual(SiriReport.clock(hours: 142.5), "142:30")
    }
}
