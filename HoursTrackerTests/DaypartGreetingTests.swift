import XCTest
@testable import HoursTracker

final class DaypartGreetingTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = hour
        return calendar.date(from: components)!
    }

    func testMorningAfternoonEveningNightWindows() {
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 7), calendar: calendar), .morning)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 13), calendar: calendar), .afternoon)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 19), calendar: calendar), .evening)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 23), calendar: calendar), .night)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 3), calendar: calendar), .night)
    }
}
