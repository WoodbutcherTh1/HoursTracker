import XCTest
@testable import HoursTracker

final class ShiftKindTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testEveningStartIsNotNightYet() {
        let start = date(2026, 10, 24, 20, 3)
        XCTAssertEqual(ShiftKind.of(clockIn: start, clockOut: nil, storedNight: false, now: date(2026, 10, 24, 20, 4), calendar: calendar), .evening)
        XCTAssertEqual(ShiftKind.of(clockIn: start, clockOut: nil, storedNight: false, now: date(2026, 10, 24, 23, 0), calendar: calendar), .evening)
    }

    func testBecomesNightAfterTwoHoursInTheWindow() {
        let start = date(2026, 10, 24, 20, 3)
        XCTAssertEqual(ShiftKind.of(clockIn: start, clockOut: nil, storedNight: false, now: date(2026, 10, 25, 0, 5), calendar: calendar), .night)
    }

    func testMorningAndNightStarts() {
        XCTAssertEqual(ShiftKind.of(clockIn: date(2026, 10, 24, 7), clockOut: nil, storedNight: false, now: date(2026, 10, 24, 7, 5), calendar: calendar), .morning)
        XCTAssertEqual(ShiftKind.of(clockIn: date(2026, 10, 24, 22, 30), clockOut: nil, storedNight: false, now: date(2026, 10, 24, 22, 31), calendar: calendar), .night)
    }

    /// Clocks go back at 02:00 on 25 Oct 2026 in Israel: the night is an hour longer
    /// and the real worked time counts.
    func testNightAcrossClockChange() {
        let start = date(2026, 10, 24, 22)
        let end = date(2026, 10, 25, 6)
        XCTAssertEqual(end.timeIntervalSince(start), 9 * 3600)
        XCTAssertTrue(WorkSession.qualifiesAsNightShift(clockIn: start, clockOut: end, calendar: calendar))
        // 21:00 → 23:30 is only 1.5h of night; with the extra hour 21:00 → 04:00 is plenty.
        XCTAssertFalse(WorkSession.qualifiesAsNightShift(clockIn: date(2026, 10, 24, 21), clockOut: date(2026, 10, 24, 23, 30), calendar: calendar))
    }
}
