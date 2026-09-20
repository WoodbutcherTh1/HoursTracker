import XCTest
@testable import HoursTracker

/// The Watch previously re-implemented the greeting hour bands inline and drifted
/// (evening cutoff 17–22 vs the phone's 17–21). Both surfaces now compile the same
/// shared `DaypartGreeting` — these tests pin the shared logic so the bands can
/// never silently diverge again.
final class DaypartGreetingParityTests: XCTestCase {

    private func date(atHour hour: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    func testHourBands() {
        let calendar = Calendar.current
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 5, calendar: calendar)), .morning)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 11, calendar: calendar)), .morning)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 12, calendar: calendar)), .afternoon)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 16, calendar: calendar)), .afternoon)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 17, calendar: calendar)), .evening)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 20, calendar: calendar)), .evening)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 21, calendar: calendar)), .night)
        XCTAssertEqual(DaypartGreeting.current(at: date(atHour: 4, calendar: calendar)), .night)
    }

    func testPersonalizedGreetingUsesFirstNameAndIsolatesRTL() {
        let greeting = DaypartGreeting.morning.title(withName: "Hmam Kaadna")
        XCTAssertTrue(greeting.contains("Hmam"), "expected first-name personalization, got: \(greeting)")
        // Bidi isolates wrap the Latin name so it can't scramble an RTL sentence.
        XCTAssertTrue(greeting.contains("\u{2068}Hmam\u{2069}"))
    }

    func testBlankNameFallsBackToPlainGreeting() {
        XCTAssertEqual(DaypartGreeting.evening.title(withName: "   "), DaypartGreeting.evening.title)
        XCTAssertEqual(DaypartGreeting.evening.title(withName: nil), DaypartGreeting.evening.title)
        XCTAssertEqual(DaypartGreeting.evening.title(withName: ""), DaypartGreeting.evening.title)
    }
}
