import XCTest
@testable import HoursTracker

final class WorkSessionBreakTests: XCTestCase {
    private let clockIn = TestData.date(2026, 3, 10, 8)

    private func openSession() -> WorkSession {
        WorkSession(date: clockIn, clockIn: clockIn)
    }

    func testStartAndEndBreakRecordsMinutes() {
        var session = openSession()
        XCTAssertTrue(session.startBreak(at: clockIn.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(session.isOnBreak)
        XCTAssertTrue(session.endBreak(at: clockIn.addingTimeInterval(4 * 3600 + 30 * 60)))
        XCTAssertFalse(session.isOnBreak)
        XCTAssertEqual(session.breakMinutes, 30)
        XCTAssertEqual(session.breaks.count, 1)
    }

    func testCannotStartSecondBreakWhileOneIsRunning() {
        var session = openSession()
        XCTAssertTrue(session.startBreak(at: clockIn.addingTimeInterval(3600)))
        XCTAssertFalse(session.startBreak(at: clockIn.addingTimeInterval(3700)))
        XCTAssertEqual(session.breaks.count, 1)
    }

    func testCannotStartBreakOnClosedShift() {
        var session = openSession()
        session.clockOut = clockIn.addingTimeInterval(8 * 3600)
        XCTAssertFalse(session.startBreak(at: clockIn.addingTimeInterval(3600)))
        XCTAssertFalse(session.isOnBreak)
    }

    func testMultipleBreaksAccumulate() {
        var session = openSession()
        session.startBreak(at: clockIn.addingTimeInterval(2 * 3600))
        session.endBreak(at: clockIn.addingTimeInterval(2 * 3600 + 10 * 60))
        session.startBreak(at: clockIn.addingTimeInterval(5 * 3600))
        session.endBreak(at: clockIn.addingTimeInterval(5 * 3600 + 20 * 60))
        XCTAssertEqual(session.breakMinutes, 30)
    }

    func testClosingOpenBreakAtClockOut() {
        var session = openSession()
        session.startBreak(at: clockIn.addingTimeInterval(7 * 3600 + 45 * 60))
        let out = clockIn.addingTimeInterval(8 * 3600)
        session.clockOut = out
        session.closeOpenBreak(at: out)
        XCTAssertEqual(session.breakMinutes, 15)
        XCTAssertFalse(session.breaks.contains(where: \.isOpen))
    }

    func testRecordedBreakSuppressesDefaultBreak() {
        var settings = WorkplaceSettings.default
        settings.defaultBreakMinutes = 30
        var session = openSession()
        session.startBreak(at: clockIn.addingTimeInterval(4 * 3600))
        session.endBreak(at: clockIn.addingTimeInterval(4 * 3600 + 10 * 60))
        session.clockOut = clockIn.addingTimeInterval(9 * 3600)
        session.applyDefaultBreakIfNeeded(settings: settings)
        XCTAssertEqual(session.breakMinutes, 10)
    }

    func testDefaultBreakStillAppliesWithoutRecordedBreaks() {
        var settings = WorkplaceSettings.default
        settings.defaultBreakMinutes = 30
        var session = openSession()
        session.clockOut = clockIn.addingTimeInterval(9 * 3600)
        session.applyDefaultBreakIfNeeded(settings: settings)
        XCTAssertEqual(session.breakMinutes, 30)
    }

    func testPaidElapsedExcludesRunningBreak() {
        var session = openSession()
        session.startBreak(at: clockIn.addingTimeInterval(3600))
        let now = clockIn.addingTimeInterval(3600 + 20 * 60)
        XCTAssertEqual(session.paidElapsedSeconds(now: now), 3600, accuracy: 0.5)
    }

    func testLegacyJSONWithoutBreaksDecodes() throws {
        let legacy = WorkSession(date: clockIn, clockIn: clockIn, clockOut: clockIn.addingTimeInterval(3600), breakMinutes: 15)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "breaks")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkSession.self, from: data)
        XCTAssertEqual(decoded.breaks, [])
        XCTAssertEqual(decoded.breakMinutes, 15)
    }

    func testBreaksRoundTripThroughJSON() throws {
        var session = openSession()
        session.startBreak(at: clockIn.addingTimeInterval(3600))
        let decoded = try JSONDecoder().decode(WorkSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.breaks, session.breaks)
        XCTAssertTrue(decoded.isOnBreak)
    }
}

final class BreakReminderPlanTests: XCTestCase {
    private let start = TestData.date(2026, 3, 10, 12)

    func testPlansHeadsUpAndBreakOver() {
        let plan = BreakReminderScheduler.plan(
            breakStart: start, now: start,
            targetMinutes: 30, leadMinutes: 5,
            endingSoonEnabled: true, overEnabled: true
        )
        XCTAssertEqual(plan, [
            .init(kind: .endingSoon, fireDate: start.addingTimeInterval(25 * 60)),
            .init(kind: .over, fireDate: start.addingTimeInterval(30 * 60))
        ])
    }

    func testRespectsDisabledToggles() {
        let onlyOver = BreakReminderScheduler.plan(
            breakStart: start, now: start,
            targetMinutes: 30, leadMinutes: 5,
            endingSoonEnabled: false, overEnabled: true
        )
        XCTAssertEqual(onlyOver.map(\.kind), [.over])

        let none = BreakReminderScheduler.plan(
            breakStart: start, now: start,
            targetMinutes: 30, leadMinutes: 5,
            endingSoonEnabled: false, overEnabled: false
        )
        XCTAssertTrue(none.isEmpty)
    }

    func testSkipsHeadsUpWhenLeadIsNotShorterThanBreak() {
        let plan = BreakReminderScheduler.plan(
            breakStart: start, now: start,
            targetMinutes: 5, leadMinutes: 5,
            endingSoonEnabled: true, overEnabled: true
        )
        XCTAssertEqual(plan.map(\.kind), [.over])
    }

    func testSkipsRemindersAlreadyInThePast() {
        let plan = BreakReminderScheduler.plan(
            breakStart: start, now: start.addingTimeInterval(27 * 60),
            targetMinutes: 30, leadMinutes: 5,
            endingSoonEnabled: true, overEnabled: true
        )
        XCTAssertEqual(plan.map(\.kind), [.over])
    }
}
