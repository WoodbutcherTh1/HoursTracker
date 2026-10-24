import XCTest
@testable import HoursTracker

@MainActor
final class UpdateReminderTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateReminderCenter.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(UpdateReminderCenter.isNewer("1.1", than: "1.0"))
        XCTAssertTrue(UpdateReminderCenter.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateReminderCenter.isNewer("1.9", than: "1.9"))
        XCTAssertFalse(UpdateReminderCenter.isNewer("1.9.0", than: "1.9"))
        XCTAssertFalse(UpdateReminderCenter.isNewer("1.8", than: "1.9"))
    }

    func testFiveAttemptsWithGrowingGapsThenStop() {
        let now = Date()
        let days = (1...5).map { UpdateReminderCenter.nextEligibleDate(afterAttempts: $0, from: now).map { Int($0.timeIntervalSince(now) / 86_400) } }
        XCTAssertEqual(days, [3, 7, 14, 21, nil])
    }
}
