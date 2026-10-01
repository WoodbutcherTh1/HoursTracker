import XCTest
@testable import HoursTracker

final class DaypartGreetingTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testMorningAfternoonEveningNightWindows() {
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 7), calendar: calendar), .morning)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 13), calendar: calendar), .afternoon)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 19), calendar: calendar), .evening)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 23), calendar: calendar), .night)
        XCTAssertEqual(DaypartGreeting.current(at: date(hour: 3), calendar: calendar), .night)
    }

    /// Morning 05:00–11:59 · afternoon 12:00–17:59 · evening 18:00–22:59 · night 23:00–04:59.
    func testBoundariesFlipOnTheMinute() {
        let cases: [(Int, Int, DaypartGreeting)] = [
            (4, 59, .night), (5, 0, .morning),
            (11, 59, .morning), (12, 0, .afternoon),
            (17, 59, .afternoon), (18, 0, .evening),
            (22, 59, .evening), (23, 0, .night),
            (0, 0, .night)
        ]
        for (hour, minute, expected) in cases {
            XCTAssertEqual(
                DaypartGreeting.current(at: date(hour: hour, minute: minute), calendar: calendar),
                expected,
                String(format: "%02d:%02d", hour, minute)
            )
        }
    }

    /// "Good night" sounds like a goodbye to a night-shift worker; night greets like evening.
    func testNightGreetsLikeEvening() {
        XCTAssertEqual(DaypartGreeting.night.title, DaypartGreeting.evening.title)
        XCTAssertEqual(DaypartGreeting.night.title(withName: "Dana"), DaypartGreeting.evening.title(withName: "Dana"))
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
            L10n.homeGreetingEveningName(isolated)
        )
        XCTAssertFalse(DaypartGreeting.night.title(withName: "Dana Weiss").contains("Weiss"))
    }
}
