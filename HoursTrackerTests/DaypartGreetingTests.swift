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

    func testTitleWithNameFormatsFirstName() {
        let isolated = "\u{2068}Dana\u{2069}"
        XCTAssertEqual(
            DaypartGreeting.morning.title(withName: "Dana"),
            L10n.homeGreetingMorningName(isolated)
        )
        XCTAssertEqual(
            DaypartGreeting.afternoon.title(withName: "Dana"),
            L10n.homeGreetingAfternoonName(isolated)
        )
    }

    func testTitleWithEmptyOrWhitespaceNameMatchesPlainTitle() {
        XCTAssertEqual(DaypartGreeting.morning.title(withName: nil), DaypartGreeting.morning.title)
        XCTAssertEqual(DaypartGreeting.morning.title(withName: ""), DaypartGreeting.morning.title)
        XCTAssertEqual(DaypartGreeting.morning.title(withName: "   "), DaypartGreeting.morning.title)
        XCTAssertEqual(DaypartGreeting.evening.title(withName: "\n\t"), DaypartGreeting.evening.title)
    }

    func testFirstNameUsesOnlyFirstToken() {
        XCTAssertEqual(DaypartGreeting.firstName(from: "Dana Weiss"), "Dana")
        XCTAssertEqual(DaypartGreeting.firstName(from: "  יוסי כהן  "), "יוסי")
        XCTAssertNil(DaypartGreeting.firstName(from: nil))
        XCTAssertNil(DaypartGreeting.firstName(from: "   "))

        let isolated = "\u{2068}Dana\u{2069}"
        XCTAssertEqual(
            DaypartGreeting.night.title(withName: "Dana Weiss Cohen"),
            L10n.homeGreetingNightName(isolated)
        )
        XCTAssertFalse(DaypartGreeting.night.title(withName: "Dana Weiss").contains("Weiss"))
    }
}
