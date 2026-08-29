import XCTest
@testable import HoursTracker

final class AssistantToolboxTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private var settings = WorkplaceSettings.default

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        settings = .default
    }

    private func date(month: Int = 8, day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func session(
        month: Int = 8,
        day: Int,
        startHour: Int = 9,
        hours: Double = 8
    ) -> WorkSession {
        let clockIn = date(month: month, day: day, hour: startHour)
        return WorkSession(
            date: calendar.startOfDay(for: clockIn),
            clockIn: clockIn,
            clockOut: clockIn.addingTimeInterval(hours * 3600)
        )
    }

    // MARK: - Date range

    func testDateRangeIsInclusiveAtBothEnds() {
        let sessions = [session(day: 4), session(day: 5), session(day: 6), session(day: 7)]

        let filtered = AssistantToolbox.filterSessionsByDateRange(
            sessions,
            start: date(day: 5),
            end: date(day: 6),
            calendar: calendar
        )

        XCTAssertEqual(filtered.count, 2)
    }

    func testDateRangeToleratesReversedBounds() {
        let sessions = [session(day: 4), session(day: 5), session(day: 9)]

        let filtered = AssistantToolbox.filterSessionsByDateRange(
            sessions,
            start: date(day: 9),
            end: date(day: 4),
            calendar: calendar
        )

        XCTAssertEqual(filtered.count, 3)
    }

    // MARK: - Time of day

    func testEveningFilterKeepsOnlyLateStarts() {
        let sessions = [
            session(day: 3, startHour: 8),
            session(day: 4, startHour: 17),
            session(day: 5, startHour: 22)
        ]

        let evening = AssistantToolbox.filterSessionsByClockInAfter(
            sessions,
            minutesFromMidnight: 17 * 60,
            calendar: calendar
        )

        XCTAssertEqual(evening.count, 2)
    }

    func testMorningFilterKeepsOnlyEarlyStarts() {
        let sessions = [
            session(day: 3, startHour: 6),
            session(day: 4, startHour: 17)
        ]

        let morning = AssistantToolbox.filterSessionsByClockInBefore(
            sessions,
            minutesFromMidnight: 12 * 60,
            calendar: calendar
        )

        XCTAssertEqual(morning.count, 1)
    }

    func testParseTimeOfDayRejectsNonsenseRatherThanDefaultingToMidnight() {
        XCTAssertEqual(AssistantToolbox.parseTimeOfDay("17:30"), 17 * 60 + 30)
        XCTAssertEqual(AssistantToolbox.parseTimeOfDay("00:00"), 0)
        XCTAssertNil(AssistantToolbox.parseTimeOfDay("evening"))
        XCTAssertNil(AssistantToolbox.parseTimeOfDay("25:00"))
        XCTAssertNil(AssistantToolbox.parseTimeOfDay("17:75"))
        XCTAssertNil(AssistantToolbox.parseTimeOfDay("17"))
    }

    // MARK: - Overtime tiers

    func testOvertimeTierFilterUsesTheRealPayEngine() {
        // The default standard day is 8.6h with a 2h cap on the 125% tier, so a 12h
        // shift reaches both overtime tiers and a 6h one reaches neither.
        let long = session(day: 3, hours: 12)
        let short = session(day: 5, hours: 6)

        let ot125 = AssistantToolbox.filterSessionsByOvertimeTier(
            [long, short],
            tier: .ot125,
            settings: settings,
            calendar: calendar
        )
        XCTAssertEqual(ot125.map(\.id), [long.id])

        let regular = AssistantToolbox.filterSessionsByOvertimeTier(
            [long, short],
            tier: .regular,
            settings: settings,
            calendar: calendar
        )
        XCTAssertEqual(Set(regular.map(\.id)), Set([long.id, short.id]))
    }

    // MARK: - Days without sessions

    func testDaysWithoutSessionsExcludesWorkedDaysAndTheFuture() {
        let sessions = [session(day: 1), session(day: 2), session(day: 2, startHour: 18)]
        let today = date(day: 5)

        let off = AssistantToolbox.findDaysWithoutSessions(
            month: today,
            sessions: sessions,
            now: today,
            calendar: calendar
        )

        // 1st and 2nd worked; 3rd, 4th and 5th not; 6th onward hasn't happened yet.
        XCTAssertEqual(off.count, 3)
        XCTAssertEqual(off.map { calendar.component(.day, from: $0) }, [3, 4, 5])
    }

    func testDaysWithoutSessionsCoversAWholePastMonth() {
        let sessions = [session(month: 7, day: 10)]
        let july = date(month: 7, day: 15)

        let off = AssistantToolbox.findDaysWithoutSessions(
            month: july,
            sessions: sessions,
            now: date(month: 8, day: 21),
            calendar: calendar
        )

        XCTAssertEqual(off.count, 30, "July has 31 days and one of them was worked")
    }

    // MARK: - Aggregation

    func testAggregatePayIgnoresOpenShifts() {
        let clockIn = date(day: 6, hour: 9)
        let open = WorkSession(
            date: calendar.startOfDay(for: clockIn),
            clockIn: clockIn,
            clockOut: nil
        )
        let closed = session(day: 5, hours: 8)

        let totals = AssistantToolbox.aggregatePay(sessions: [closed, open], settings: settings)
        let expected = OvertimeCalculator.aggregate(sessions: [closed], settings: settings)

        XCTAssertEqual(totals.totalHours, expected.totalHours, accuracy: 0.0001)
        XCTAssertEqual(totals.totalPay, expected.totalPay, accuracy: 0.0001)
    }

    func testDistinctDaysCollapsesRepeatShifts() {
        let sessions = [
            session(day: 3, startHour: 8, hours: 4),
            session(day: 3, startHour: 17, hours: 4),
            session(day: 4)
        ]

        XCTAssertEqual(AssistantToolbox.distinctDays(in: sessions, calendar: calendar).count, 2)
    }
}
