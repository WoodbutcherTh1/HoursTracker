import XCTest
@testable import HoursTracker

final class HistoryPeriodWeekRowsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.startOfDay(for: calendar.date(from: components)!)
    }

    func testStartOfWeekHonorsFirstWeekday() {
        // 2026-07-15 is a Wednesday.
        let wednesday = day(2026, 7, 15)
        XCTAssertEqual(HistoryPeriodHelper.startOfWeek(containing: wednesday, calendar: calendar), day(2026, 7, 12))

        calendar.firstWeekday = 2 // Monday
        XCTAssertEqual(HistoryPeriodHelper.startOfWeek(containing: wednesday, calendar: calendar), day(2026, 7, 13))
    }

    func testWeekRowsPadsMidMonthPayrollPeriod() {
        // Payroll 18 Jun … 17 Jul 2026. 18 Jun is Thursday → pad Sun–Wed before.
        let period = PayrollPeriod(
            start: day(2026, 6, 18),
            end: day(2026, 7, 17),
            labelMonth: day(2026, 6, 1)
        )

        let weeks = HistoryPeriodHelper.weekRows(for: period, calendar: calendar)
        XCTAssertFalse(weeks.isEmpty)
        XCTAssertTrue(weeks.allSatisfy { $0.days.count == 7 })

        let first = weeks[0].days
        XCTAssertEqual(first.map(\.date), [
            day(2026, 6, 14), day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17),
            day(2026, 6, 18), day(2026, 6, 19), day(2026, 6, 20)
        ])
        XCTAssertEqual(first.map(\.isInPeriod), [false, false, false, false, true, true, true])

        let last = weeks[weeks.count - 1].days
        // 17 Jul 2026 is Friday → week Sun 12 … Sat 18, with Sat padded out.
        XCTAssertEqual(last.last?.date, day(2026, 7, 18))
        XCTAssertEqual(last.last?.isInPeriod, false)
        XCTAssertEqual(last.first { calendar.isDate($0.date, inSameDayAs: day(2026, 7, 17)) }?.isInPeriod, true)

        let inPeriodCount = weeks.flatMap(\.days).filter(\.isInPeriod).count
        XCTAssertEqual(inPeriodCount, period.days.count)
    }

    func testWeekIndexFindsSelectedDay() {
        let period = PayrollPeriod(
            start: day(2026, 6, 18),
            end: day(2026, 7, 17),
            labelMonth: day(2026, 6, 1)
        )
        let weeks = HistoryPeriodHelper.weekRows(for: period, calendar: calendar)
        let index = HistoryPeriodHelper.weekIndex(
            containing: day(2026, 7, 1),
            in: weeks,
            calendar: calendar
        )
        XCTAssertNotNil(index)
        XCTAssertTrue(
            weeks[index!].days.contains { calendar.isDate($0.date, inSameDayAs: day(2026, 7, 1)) }
        )
    }
}
