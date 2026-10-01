import XCTest
@testable import HoursTracker

final class OnboardingSetupTests: XCTestCase {
    // MARK: Rate parsing

    func testParsesWesternArabicIndicAndCommaDecimals() {
        XCTAssertEqual(OnboardingEstimate.parseRate("45"), 45)
        XCTAssertEqual(OnboardingEstimate.parseRate("45.5"), 45.5)
        XCTAssertEqual(OnboardingEstimate.parseRate("45,5"), 45.5)
        XCTAssertEqual(OnboardingEstimate.parseRate("٤٥٫٥"), 45.5)
        XCTAssertEqual(OnboardingEstimate.parseRate(" 38 "), 38)
    }

    func testRejectsOutOfRangeOrGarbageRates() {
        XCTAssertNil(OnboardingEstimate.parseRate(""))
        XCTAssertNil(OnboardingEstimate.parseRate("0"))
        XCTAssertNil(OnboardingEstimate.parseRate("501"))
        XCTAssertNil(OnboardingEstimate.parseRate("abc"))
    }

    // MARK: Estimates (priced by the real engine)

    func testEightHourPreviewIsRateTimesHoursPlusDailyAllowance() {
        let settings = TestData.settings(hourlyRate: 50)
        let day = OnboardingEstimate.day(settings: settings)
        XCTAssertEqual(day.totalHours, 8)
        XCTAssertEqual(day.ot125Hours, 0)
        XCTAssertEqual(day.grossPay, 8 * 50 + settings.dailyGasAllowance, accuracy: 0.001)
    }

    func testWeeklyEstimateSpreadsHoursOverWorkdays() {
        let settings = TestData.settings(hourlyRate: 50)
        // 40h over 5 days = 8h/day, under the standard day → no overtime.
        let weekly = OnboardingEstimate.weeklyGross(settings: settings, weeklyHours: 40, workdayCount: 5)
        XCTAssertEqual(weekly, 40 * 50 + 5 * settings.dailyGasAllowance, accuracy: 0.001)
    }

    // MARK: Week pattern

    func testDefaultWeeklyHoursPerPattern() {
        XCTAssertEqual(WeekPattern.fiveDays.defaultWeeklyHours(custom: []), 42)
        XCTAssertEqual(WeekPattern.sixDays.defaultWeeklyHours(custom: []), 42)
        XCTAssertEqual(WeekPattern.varies.defaultWeeklyHours(custom: []), 30)
        XCTAssertEqual(WeekPattern.custom.defaultWeeklyHours(custom: [6, 7, 1]), 24)
        XCTAssertEqual(WeekPattern.custom.defaultWeeklyHours(custom: Set(1...7)), 56)
        // Nothing picked yet falls back to a 5-day week.
        XCTAssertEqual(WeekPattern.custom.defaultWeeklyHours(custom: []), 40)
    }

    func testCustomWorkdaysCanIncludeFridayAndSaturday() {
        XCTAssertEqual(WeekPattern.custom.workdays(custom: [6, 7]), [6, 7])
    }

    // MARK: DISPLAY ONLY — never used in pay math

    /// The onboarding's weekly goal and week pattern must not move any pay figure:
    /// the same sessions and settings price identically whatever they are set to.
    func testDisplayOnlyPreferencesNeverReachPayMath() {
        let display = DisplayPreferences.shared
        let savedGoal = display.weeklyGoalHoursDisplayOnly
        let savedPattern = display.weekPattern
        let savedDays = display.customWorkdays
        defer {
            display.weeklyGoalHoursDisplayOnly = savedGoal
            display.weekPattern = savedPattern
            display.customWorkdays = savedDays
        }

        let settings = TestData.settings(hourlyRate: 60)
        let sessions = [
            TestData.session(day: 4, inHour: 8, outHour: 19),
            TestData.session(day: 5, inHour: 7, outHour: 17),
            TestData.session(day: 6, inHour: 9, outHour: 13)
        ]

        display.weeklyGoalHoursDisplayOnly = 10
        display.weekPattern = .fiveDays
        display.customWorkdays = []
        let before = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
        let quickBefore = OvertimeCalculator.breakdown(totalHours: 11, settings: settings)

        display.weeklyGoalHoursDisplayOnly = 60
        display.weekPattern = .custom
        display.customWorkdays = [6, 7]
        let after = OvertimeCalculator.aggregate(sessions: sessions, settings: settings)
        let quickAfter = OvertimeCalculator.breakdown(totalHours: 11, settings: settings)

        XCTAssertEqual(before.grossPay, after.grossPay, accuracy: 0.0001)
        XCTAssertEqual(before.netPay, after.netPay, accuracy: 0.0001)
        XCTAssertEqual(before.ot125Hours, after.ot125Hours, accuracy: 0.0001)
        XCTAssertEqual(before.ot150Hours, after.ot150Hours, accuracy: 0.0001)
        XCTAssertEqual(quickBefore.grossPay, quickAfter.grossPay, accuracy: 0.0001)
        // And the legal weekly standard is untouched by the display goal.
        XCTAssertEqual(settings.weeklyStandardHours, TestData.settings(hourlyRate: 60).weeklyStandardHours)
    }

    func testDisplayPreferencesRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OnboardingSetupTests-\(UUID().uuidString)"))
        let display = DisplayPreferences(defaults: defaults)
        XCTAssertNil(display.weeklyGoalHoursDisplayOnly)
        display.weeklyGoalHoursDisplayOnly = 35
        display.weekPattern = .custom
        display.customWorkdays = [6, 7]
        XCTAssertEqual(display.weeklyGoalHoursDisplayOnly, 35)
        XCTAssertEqual(display.weekPattern, .custom)
        XCTAssertEqual(display.customWorkdays, [6, 7])
    }
}
