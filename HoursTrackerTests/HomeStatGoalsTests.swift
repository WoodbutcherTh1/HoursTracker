import XCTest
@testable import HoursTracker

@MainActor
final class HomeStatGoalsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    // MARK: Today

    func testTodayTargetIsWeeklyGoalOverWorkdays() {
        let goals = HomeStatGoals(weeklyGoalHours: 42, weekPattern: .fiveDays, customWorkdays: [])
        let monday = date(2026, 9, 28)
        XCTAssertEqual(goals.todayHoursTarget(on: monday, calendar: calendar) ?? 0, 8.4, accuracy: 0.001)
    }

    func testDayOffHasNoTodayBar() {
        let goals = HomeStatGoals(weeklyGoalHours: 42, weekPattern: .fiveDays, customWorkdays: [])
        let saturday = date(2026, 10, 3)
        XCTAssertNil(goals.todayHoursTarget(on: saturday, calendar: calendar))
    }

    // MARK: Varies / nothing set

    func testVariesWeekHasNoTodayOrMonthBarButKeepsTheWeeklyGoal() {
        let goals = HomeStatGoals(weeklyGoalHours: 30, weekPattern: .varies, customWorkdays: [])
        XCTAssertNil(goals.todayHoursTarget(on: date(2026, 9, 28), calendar: calendar))
        XCTAssertNil(goals.monthShiftTarget(for: date(2026, 9, 28), calendar: calendar))
        XCTAssertEqual(goals.weekHoursTarget, 30)
    }

    func testNoAnswersMeansNoBars() {
        let goals = HomeStatGoals(weeklyGoalHours: nil, weekPattern: nil, customWorkdays: [])
        XCTAssertNil(goals.todayHoursTarget(on: date(2026, 9, 28), calendar: calendar))
        XCTAssertNil(goals.weekHoursTarget)
        XCTAssertNil(goals.monthShiftTarget(for: date(2026, 9, 28), calendar: calendar))
        XCTAssertNil(HomeStatGoals.progress(5, target: nil), "No target must mean no bar, not an empty 0% bar")
    }

    // MARK: Month

    func testMonthTargetCountsWorkdaysOfThePattern() {
        let sixDays = HomeStatGoals(weeklyGoalHours: nil, weekPattern: .sixDays, customWorkdays: [])
        // February 2026 is exactly four weeks (starts on a Sunday).
        XCTAssertEqual(sixDays.monthShiftTarget(for: date(2026, 2, 10), calendar: calendar), 24)

        // Sundays + Tuesdays in September 2026: 4 + 5.
        let custom = HomeStatGoals(weeklyGoalHours: nil, weekPattern: .custom, customWorkdays: [1, 3])
        XCTAssertEqual(custom.monthShiftTarget(for: date(2026, 9, 15), calendar: calendar), 9)
    }

    func testProgressClampsToAFullBar() {
        XCTAssertEqual(HomeStatGoals.progress(4.2, target: 8.4), 0.5)
        XCTAssertEqual(HomeStatGoals.progress(12, target: 8.4), 1)
        XCTAssertEqual(HomeStatGoals.progress(-1, target: 8.4), 0)
    }

    // MARK: Short card titles

    /// The 3-across card shows the short title; it must exist in every language and
    /// never be longer than the full one (which VoiceOver keeps reading).
    func testShortTitlesAreTranslatedAndNeverLonger() {
        let keys = [("home.stat.month", "home.stat.month.short"),
                    ("home.stat.week", "home.stat.week.short"),
                    ("home.stat.today", "home.stat.today.short")]
        for language in [AppLocale.Language.english, .hebrew, .arabic, .russian] {
            for (full, short) in keys {
                let fullText = AppLocale.localizedString(full, language: language)
                let shortText = AppLocale.localizedString(short, language: language)
                XCTAssertNotEqual(shortText, short, "\(short) missing in \(language)")
                XCTAssertLessThanOrEqual(shortText.count, fullText.count, "\(short) is longer than \(full) in \(language)")
            }
        }
        XCTAssertEqual(AppLocale.localizedString("home.stat.month.short", language: .english), "Month")
    }

    // MARK: Reorder without dragging

    func testShiftMovesOneSlotAndStopsAtTheEdges() {
        let layout = HomeStatsLayout.shared
        let saved = layout.order
        defer { layout.order = saved }

        layout.order = [.month, .week, .today]
        XCTAssertFalse(layout.canShift(.month, by: -1))
        layout.shift(.month, by: -1)
        XCTAssertEqual(layout.order, [.month, .week, .today], "Moving the first card earlier is a no-op")

        layout.shift(.month, by: 1)
        XCTAssertEqual(layout.order, [.week, .month, .today])
        layout.shift(.today, by: -1)
        XCTAssertEqual(layout.order, [.week, .today, .month])
        XCTAssertFalse(layout.canShift(.month, by: 1))
    }
}
