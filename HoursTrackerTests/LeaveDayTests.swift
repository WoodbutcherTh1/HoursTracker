import XCTest
@testable import HoursTracker

final class LeaveDayTests: XCTestCase {
    private let calendar = Calendar.current

    // January 2026 has no Israeli statutory holiday, so only marked days count.
    private var januaryStart: Date { TestData.date(2026, 1, 1) }
    private var januaryEnd: Date { TestData.date(2026, 1, 31) }

    func testCountsDistinctDaysPerKind() {
        let sessions = [
            TestData.sickDay(day: 4),
            TestData.sickDay(day: 5),
            TestData.session(day: 7, dayType: .holiday),
            TestData.session(day: 8, dayType: .regular)
        ]
        let leave = [
            LeaveDay(date: TestData.date(2026, 1, 12), kind: .vacation),
            LeaveDay(date: TestData.date(2026, 1, 13), kind: .vacation),
            LeaveDay(date: TestData.date(2026, 1, 20), kind: .recuperation)
        ]

        let counts = PeriodDayCounts.count(
            sessions: sessions,
            leaveDays: leave,
            from: januaryStart,
            through: januaryEnd,
            calendar: calendar
        )

        XCTAssertEqual(counts, PeriodDayCounts(holiday: 1, vacation: 2, recuperation: 1, sick: 2))
    }

    func testDaysOutsideTheRangeAreIgnored() {
        let leave = [
            LeaveDay(date: TestData.date(2026, 1, 12), kind: .vacation),
            LeaveDay(date: TestData.date(2026, 2, 2), kind: .vacation)
        ]
        let counts = PeriodDayCounts.count(
            sessions: [TestData.sickDay(month: 2, day: 3)],
            leaveDays: leave,
            from: januaryStart,
            through: januaryEnd,
            calendar: calendar
        )
        XCTAssertEqual(counts.vacation, 1)
        XCTAssertEqual(counts.sick, 0)
    }

    func testTwoShiftsOnOneSickDayCountOnce() {
        let counts = PeriodDayCounts.count(
            sessions: [TestData.sickDay(day: 4), TestData.sickDay(day: 4)],
            leaveDays: [],
            from: januaryStart,
            through: januaryEnd,
            calendar: calendar
        )
        XCTAssertEqual(counts.sick, 1)
    }

    func testSettingsKeepLeaveDaysThroughCoding() throws {
        var settings = TestData.settings()
        settings.leaveDays = [LeaveDay(date: TestData.date(2026, 1, 12), kind: .recuperation)]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WorkplaceSettings.self, from: data)
        XCTAssertEqual(decoded.leaveDays, settings.leaveDays)
    }

    func testOlderSettingsWithoutLeaveDaysStillDecode() throws {
        let settings = TestData.settings()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        object.removeValue(forKey: "leaveDays")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkplaceSettings.self, from: data)
        XCTAssertEqual(decoded.leaveDays, [])
        XCTAssertEqual(decoded.hourlyRate, settings.hourlyRate)
    }

    func testAnUnknownLeaveKindNeverBreaksSettings() throws {
        let settings = TestData.settings()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        object["leaveDays"] = [["id": UUID().uuidString, "date": 0, "kind": "someFutureKind"]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkplaceSettings.self, from: data)
        XCTAssertEqual(decoded.leaveDays, [])
        XCTAssertEqual(decoded.workplaceName, settings.workplaceName)
    }
}
