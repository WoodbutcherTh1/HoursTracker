import XCTest
@testable import HoursTracker

final class WorkedDaysCounterTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(year: Int = 2026, month: Int = 8, day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func session(
        month: Int = 8,
        day: Int,
        startHour: Int = 9,
        hours: Double = 8,
        open: Bool = false
    ) -> WorkSession {
        let clockIn = date(month: month, day: day, hour: startHour)
        return WorkSession(
            date: calendar.startOfDay(for: clockIn),
            clockIn: clockIn,
            clockOut: open ? nil : clockIn.addingTimeInterval(hours * 3600)
        )
    }

    // MARK: - Distinct days

    func testCountsDistinctDaysNotSessions() {
        // Two separate shifts on the 3rd is still one worked day.
        let sessions = [
            session(day: 3, startHour: 8, hours: 4),
            session(day: 3, startHour: 17, hours: 4),
            session(day: 4)
        ]

        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(
                in: sessions,
                month: date(day: 15),
                calendar: calendar
            ),
            2
        )
    }

    func testOpenShiftsAreNotCountedUntilClockedOut() {
        let sessions = [session(day: 3), session(day: 4, open: true)]

        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(
                in: sessions,
                month: date(day: 15),
                calendar: calendar
            ),
            1
        )
    }

    func testOnlyCountsTheGivenCalendarMonth() {
        let sessions = [
            session(month: 7, day: 30),
            session(month: 8, day: 1),
            session(month: 8, day: 2),
            session(month: 9, day: 1)
        ]

        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(
                in: sessions,
                month: date(month: 8, day: 15),
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(
                in: sessions,
                month: date(month: 7, day: 15),
                calendar: calendar
            ),
            1
        )
    }

    func testEmptySessionsCountZero() {
        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(in: [], month: date(day: 15), calendar: calendar),
            0
        )
    }

    // MARK: - "+1?" bubble

    func testPendingDayShowsWhenTodayHasNoCompletedSessionYet() {
        let open = session(day: 5, open: true)
        let sessions = [session(day: 3), session(day: 4), open]

        XCTAssertTrue(
            WorkedDaysCounter.openShiftWouldAddADay(
                activeSession: open,
                sessions: sessions,
                month: date(day: 5),
                calendar: calendar
            )
        )
    }

    func testPendingDayHiddenWhenTodayWasAlreadyWorked() {
        // Clocked out at lunch, clocked back in — the day is already counted.
        let open = session(day: 5, startHour: 17, open: true)
        let sessions = [session(day: 5, startHour: 8, hours: 4), open]

        XCTAssertFalse(
            WorkedDaysCounter.openShiftWouldAddADay(
                activeSession: open,
                sessions: sessions,
                month: date(day: 5),
                calendar: calendar
            )
        )
    }

    func testPendingDayHiddenWithNoOpenShift() {
        let sessions = [session(day: 3), session(day: 4)]

        XCTAssertFalse(
            WorkedDaysCounter.openShiftWouldAddADay(
                activeSession: nil,
                sessions: sessions,
                month: date(day: 5),
                calendar: calendar
            )
        )
    }

    func testPendingDayHiddenWhenOpenShiftIsOutsideTheDisplayedMonth() {
        // Browsing July while a shift runs in August.
        let open = session(month: 8, day: 5, open: true)
        let sessions = [session(month: 7, day: 30), open]

        XCTAssertFalse(
            WorkedDaysCounter.openShiftWouldAddADay(
                activeSession: open,
                sessions: sessions,
                month: date(month: 7, day: 15),
                calendar: calendar
            )
        )
    }

    /// The behavior the whole feature is about: the bubble disappears at clock-out and
    /// the number goes up by exactly one at the same moment.
    func testClockingOutMovesThePendingDayIntoTheCount() {
        let open = session(day: 5, open: true)
        let before = [session(day: 3), session(day: 4), open]
        let month = date(day: 5)

        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(in: before, month: month, calendar: calendar),
            2
        )
        XCTAssertTrue(
            WorkedDaysCounter.openShiftWouldAddADay(
                activeSession: open,
                sessions: before,
                month: month,
                calendar: calendar
            )
        )

        var closed = open
        closed.clockOut = open.clockIn.addingTimeInterval(8 * 3600)
        let after = [session(day: 3), session(day: 4), closed]

        XCTAssertEqual(
            WorkedDaysCounter.distinctWorkedDays(in: after, month: month, calendar: calendar),
            3
        )
        XCTAssertFalse(
            WorkedDaysCounter.openShiftWouldAddADay(
                activeSession: nil,
                sessions: after,
                month: month,
                calendar: calendar
            )
        )
    }
}
