import XCTest
@testable import HoursTracker

final class LocationReminderPolicyTests: XCTestCase {
    func testIsWorkDayFalseOnPrimaryAndSecondRestDay() {
        var settings = TestData.settings()
        settings.restDayWeekday = 7 // Saturday
        settings.secondRestDayWeekday = 6 // Friday

        let friday = TestData.date(2026, 7, 17)
        let saturday = TestData.date(2026, 7, 18)
        let sunday = TestData.date(2026, 7, 19)

        XCTAssertFalse(LocationReminderManager.isWorkDay(friday, settings: settings))
        XCTAssertFalse(LocationReminderManager.isWorkDay(saturday, settings: settings))
        XCTAssertTrue(LocationReminderManager.isWorkDay(sunday, settings: settings))
    }

    func testIsWorkDayTrueWhenOnlyOneRestDayConfigured() {
        var settings = TestData.settings()
        settings.restDayWeekday = 7
        settings.secondRestDayWeekday = nil

        let friday = TestData.date(2026, 7, 17)
        let saturday = TestData.date(2026, 7, 18)

        XCTAssertTrue(LocationReminderManager.isWorkDay(friday, settings: settings))
        XCTAssertFalse(LocationReminderManager.isWorkDay(saturday, settings: settings))
    }

    func testNotificationTitleIsNotEmpty() {
        XCTAssertFalse(LocationReminderManager.notificationTitle().isEmpty)
    }
}
