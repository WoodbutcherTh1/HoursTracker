import XCTest
@testable import HoursTracker

final class WeekDailyHoursTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday
    }

    /// Sunday 2026-07-12 00:00 UTC through the week.
    private func dayInWeek(_ offset: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 12 + offset
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func session(
        dayOffset: Int,
        hours: Double,
        open: Bool = false
    ) -> WorkSession {
        let clockIn = dayInWeek(dayOffset, hour: 9)
        let clockOut: Date? = open ? nil : clockIn.addingTimeInterval(hours * 3600)
        return WorkSession(
            date: calendar.startOfDay(for: clockIn),
            clockIn: clockIn,
            clockOut: clockOut
        )
    }

    func testBucketsCompletedSessionsByDayOfWeek() {
        let sessions = [
            session(dayOffset: 0, hours: 8),      // Sun
            session(dayOffset: 1, hours: 4.5),    // Mon
            session(dayOffset: 1, hours: 2),      // Mon (second shift)
            session(dayOffset: 3, hours: 10),     // Wed
            session(dayOffset: 6, hours: 6)       // Sat
        ]

        let daily = HistoryPeriodHelper.dailyHoursForWeek(
            containing: dayInWeek(2),
            sessions: sessions,
            calendar: calendar
        )

        XCTAssertEqual(daily.count, 7)
        XCTAssertEqual(daily[0], 8, accuracy: 0.001)
        XCTAssertEqual(daily[1], 6.5, accuracy: 0.001)
        XCTAssertEqual(daily[2], 0, accuracy: 0.001)
        XCTAssertEqual(daily[3], 10, accuracy: 0.001)
        XCTAssertEqual(daily[4], 0, accuracy: 0.001)
        XCTAssertEqual(daily[5], 0, accuracy: 0.001)
        XCTAssertEqual(daily[6], 6, accuracy: 0.001)
    }

    func testIgnoresOpenSessions() {
        let sessions = [
            session(dayOffset: 2, hours: 8),
            session(dayOffset: 2, hours: 3, open: true)
        ]

        let daily = HistoryPeriodHelper.dailyHoursForWeek(
            containing: dayInWeek(2),
            sessions: sessions,
            calendar: calendar
        )

        XCTAssertEqual(daily[2], 8, accuracy: 0.001)
    }

    func testIgnoresSessionsOutsideWeek() {
        let outside = session(dayOffset: -1, hours: 12) // prior Saturday
        let inside = session(dayOffset: 4, hours: 7)

        let daily = HistoryPeriodHelper.dailyHoursForWeek(
            containing: dayInWeek(0),
            sessions: [outside, inside],
            calendar: calendar
        )

        XCTAssertEqual(daily.reduce(0, +), 7, accuracy: 0.001)
        XCTAssertEqual(daily[4], 7, accuracy: 0.001)
    }

    func testNormalizedHeightsZeroDaysStayFlat() {
        let heights = HistoryPeriodHelper.normalizedDayHeights([0, 8, 0, 4, 0, 0, 2])
        XCTAssertEqual(heights[0], 0, accuracy: 0.001)
        XCTAssertEqual(heights[1], 1, accuracy: 0.001)
        XCTAssertEqual(heights[2], 0, accuracy: 0.001)
        XCTAssertEqual(heights[3], 0.5, accuracy: 0.001)
        XCTAssertEqual(heights[6], max(0.12, 2.0 / 8.0), accuracy: 0.001)
    }

    func testNormalizedHeightsAllZero() {
        let heights = HistoryPeriodHelper.normalizedDayHeights([0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(heights, Array(repeating: 0, count: 7))
    }

    func testFormatHoursClockMatchesHistory() {
        XCTAssertEqual(HistoryPeriodHelper.formatHoursClock(8.5), "08:30")
        XCTAssertEqual(HistoryPeriodHelper.formatHoursClock(0), "00:00")
        XCTAssertEqual(HistoryPeriodHelper.formatHoursClock(10), "10:00")
    }
}
