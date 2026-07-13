import XCTest
@testable import HoursTracker

final class ClockOutEstimationTests: XCTestCase {
    private let now = TestData.date(2026, 6, 15, 12, 0)

    private func hourMinute(_ date: Date?) -> (Int, Int)? {
        guard let date else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour!, components.minute!)
    }

    func testNoCompletedSessionsReturnsNil() {
        let open = TestData.session(day: 1, outHour: nil)

        XCTAssertNil(LocationReminderManager.estimatedClockOutTime(from: [], now: now))
        XCTAssertNil(LocationReminderManager.estimatedClockOutTime(from: [open], now: now))
    }

    func testSingleSessionUsesItsClockOutTime() {
        let session = TestData.session(day: 1, outHour: 17)

        let estimate = LocationReminderManager.estimatedClockOutTime(from: [session], now: now)

        XCTAssertEqual(hourMinute(estimate)?.0, 17)
        XCTAssertEqual(hourMinute(estimate)?.1, 0)
    }

    func testAverageRoundsUpToTenMinutes() {
        // 17:00 and 17:30 average to 17:15, which rounds up to 17:20.
        let first = TestData.session(day: 1, outHour: 17, outMinute: 0)
        let second = TestData.session(day: 2, outHour: 17, outMinute: 30)

        let estimate = LocationReminderManager.estimatedClockOutTime(from: [first, second], now: now)

        XCTAssertEqual(hourMinute(estimate)?.0, 17)
        XCTAssertEqual(hourMinute(estimate)?.1, 20)
    }

    func testEstimateProjectsOntoTheCurrentDay() {
        let session = TestData.session(day: 1, outHour: 17)

        let estimate = LocationReminderManager.estimatedClockOutTime(from: [session], now: now)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(Calendar.current.isDate(estimate!, inSameDayAs: now))
    }

    func testOnlyTenMostRecentSessionsAreUsed() {
        // Two old outliers at 06:00 followed by ten recent sessions at 18:00.
        // Only the ten recent ones should count, so the estimate is 18:00.
        var sessions: [WorkSession] = [
            TestData.session(day: 1, inHour: 5, outHour: 6),
            TestData.session(day: 2, inHour: 5, outHour: 6)
        ]
        for day in 3...12 {
            sessions.append(TestData.session(day: day, inHour: 9, outHour: 18))
        }

        let estimate = LocationReminderManager.estimatedClockOutTime(from: sessions, now: now)

        XCTAssertEqual(hourMinute(estimate)?.0, 18)
        XCTAssertEqual(hourMinute(estimate)?.1, 0)
    }
}
