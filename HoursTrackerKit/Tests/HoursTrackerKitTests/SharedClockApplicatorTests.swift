import XCTest
@testable import HoursTrackerKit

final class SharedClockApplicatorTests: XCTestCase {
    private var pay: WatchPaySettings {
        WatchPaySettings(
            hourlyRate: 40,
            dailyGasAllowance: 0,
            standardDayHours: 8.6,
            ot125HoursCap: 2,
            nightStandardDayHours: 7,
            defaultBreakMinutes: 0,
            restDayWeekday: 7,
            secondRestDayWeekday: nil,
            currencyCode: "ILS",
            language: .english
        )
    }

    func testClockInThenClockOut() {
        let clockIn = WatchClockEvent.makeClockIn(at: Date().addingTimeInterval(-3600))
        let clockOut = WatchClockEvent.makeClockOut(
            sessionID: clockIn.sessionID,
            at: Date()
        )
        let merged = SharedClockApplicator.merge(
            phone: [],
            pending: [clockIn, clockOut],
            pay: pay
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].isOpen)
        XCTAssertEqual(merged[0].id, clockIn.sessionID)
    }

    func testDuplicateClockInIsNoOp() {
        let event = WatchClockEvent.makeClockIn()
        let once = SharedClockApplicator.merge(phone: [], pending: [event], pay: pay)
        let twice = SharedClockApplicator.merge(phone: once, pending: [event], pay: pay)
        XCTAssertEqual(twice.count, 1)
        XCTAssertEqual(once[0].id, twice[0].id)
    }

    func testSecondClockInWhileOpenIsRejected() {
        let first = WatchClockEvent.makeClockIn(at: Date().addingTimeInterval(-1800))
        let second = WatchClockEvent.makeClockIn(at: Date())
        let merged = SharedClockApplicator.merge(phone: [], pending: [first, second], pay: pay)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, first.sessionID)
    }
}
