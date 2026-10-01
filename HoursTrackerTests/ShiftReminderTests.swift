import XCTest
@testable import HoursTracker

final class ShiftReminderTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func shift(_ start: Date, hours: Double) -> WorkSession {
        WorkSession(
            date: calendar.startOfDay(for: start),
            clockIn: start,
            clockOut: start.addingTimeInterval(hours * 3600)
        )
    }

    /// Settings with Saturday as the only rest day.
    private var settings: WorkplaceSettings {
        var settings = WorkplaceSettings.default
        settings.restDayWeekday = 7
        settings.secondRestDayWeekday = nil
        return settings
    }

    // 2026-10-04 and 2026-10-11 are Sundays; 2026-10-18 is the Sunday after.
    private var twoSundays: [WorkSession] {
        [shift(date(2026, 10, 4, 7, 0), hours: 9), shift(date(2026, 10, 11, 7, 10), hours: 9)]
    }

    func testLearnsMedianStartAndLengthPerWeekday() {
        let schedule = ShiftSchedule.learn(from: twoSundays, now: date(2026, 10, 17, 12), calendar: calendar)
        let sunday = schedule.windows[1]
        XCTAssertEqual(sunday?.startMinutes, 7 * 60 + 5)
        XCTAssertEqual(sunday?.durationMinutes, 9 * 60)
        XCTAssertEqual(sunday?.sampleCount, 2)
    }

    func testSingleShiftDoesNotMakeAWorkDay() {
        let schedule = ShiftSchedule.learn(
            from: [shift(date(2026, 10, 9, 8), hours: 8)],
            now: date(2026, 10, 17, 12),
            calendar: calendar
        )
        XCTAssertTrue(schedule.windows.isEmpty)
    }

    func testIgnoresShiftsOutsideTheLookback() {
        let old = [shift(date(2026, 6, 7, 7), hours: 9), shift(date(2026, 6, 14, 7), hours: 9)]
        let schedule = ShiftSchedule.learn(from: old, now: date(2026, 10, 17, 12), calendar: calendar)
        XCTAssertTrue(schedule.windows.isEmpty)
    }

    func testPlansStartReminderFiveMinutesBeforeUsualStart() {
        let now = date(2026, 10, 17, 12) // Saturday
        let schedule = ShiftSchedule.learn(from: twoSundays, now: now, calendar: calendar)
        let plan = ShiftReminderScheduler.plan(
            sessions: twoSundays, settings: settings, schedule: schedule,
            now: now, startEnabled: true, endEnabled: true, calendar: calendar
        )
        let starts = plan.filter { $0.kind == .start }
        XCTAssertEqual(starts.first?.fireDate, date(2026, 10, 18, 7, 0)) // 07:05 − 5 min
    }

    func testNoStartReminderOnRestDay() {
        // Learn a Saturday pattern, but Saturday is the rest day.
        let saturdays = [shift(date(2026, 10, 3, 9), hours: 5), shift(date(2026, 10, 10, 9), hours: 5)]
        let now = date(2026, 10, 16, 12)
        let schedule = ShiftSchedule.learn(from: saturdays, now: now, calendar: calendar)
        let plan = ShiftReminderScheduler.plan(
            sessions: saturdays, settings: settings, schedule: schedule,
            now: now, startEnabled: true, endEnabled: false, calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testNoStartReminderWhenAlreadyClockedInThatDay() {
        let now = date(2026, 10, 18, 6, 30) // Sunday, before the reminder
        var sessions = twoSundays
        sessions.append(WorkSession(date: calendar.startOfDay(for: now), clockIn: date(2026, 10, 18, 6, 20)))
        let schedule = ShiftSchedule.learn(from: twoSundays, now: now, calendar: calendar)
        let plan = ShiftReminderScheduler.plan(
            sessions: sessions, settings: settings, schedule: schedule,
            now: now, startEnabled: true, endEnabled: false, calendar: calendar
        )
        XCTAssertFalse(plan.contains { $0.kind == .start && calendar.isDate($0.fireDate, inSameDayAs: now) })
    }

    func testEndReminderOnlyWhileAShiftIsOpen() {
        let now = date(2026, 10, 18, 8)
        let schedule = ShiftSchedule.learn(from: twoSundays, now: now, calendar: calendar)

        let closedPlan = ShiftReminderScheduler.plan(
            sessions: twoSundays, settings: settings, schedule: schedule,
            now: now, startEnabled: false, endEnabled: true, calendar: calendar
        )
        XCTAssertTrue(closedPlan.isEmpty)

        var sessions = twoSundays
        sessions.append(WorkSession(date: calendar.startOfDay(for: now), clockIn: date(2026, 10, 18, 7, 0)))
        let openPlan = ShiftReminderScheduler.plan(
            sessions: sessions, settings: settings, schedule: schedule,
            now: now, startEnabled: false, endEnabled: true, calendar: calendar
        )
        // Usual end 07:05 + 9h = 16:05 → reminder 16:00.
        XCTAssertEqual(openPlan, [.init(id: ShiftReminderScheduler.endID, kind: .end, fireDate: date(2026, 10, 18, 16, 0))])
    }

    func testLateStartUsesUsualLengthForEndReminder() {
        let now = date(2026, 10, 18, 16, 30)
        let schedule = ShiftSchedule.learn(from: twoSundays, now: now, calendar: calendar)
        var sessions = twoSundays
        // Clocked in at 15:30 — past the usual 16:05 end minus an hour.
        sessions.append(WorkSession(date: calendar.startOfDay(for: now), clockIn: date(2026, 10, 18, 15, 30)))
        let plan = ShiftReminderScheduler.plan(
            sessions: sessions, settings: settings, schedule: schedule,
            now: now, startEnabled: false, endEnabled: true, calendar: calendar
        )
        // 15:30 + 9h − 5 min = 00:25 next day.
        XCTAssertEqual(plan.first?.fireDate, date(2026, 10, 19, 0, 25))
    }

    func testDisabledTogglesPlanNothing() {
        let now = date(2026, 10, 17, 12)
        let schedule = ShiftSchedule.learn(from: twoSundays, now: now, calendar: calendar)
        let plan = ShiftReminderScheduler.plan(
            sessions: twoSundays, settings: settings, schedule: schedule,
            now: now, startEnabled: false, endEnabled: false, calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }
}
