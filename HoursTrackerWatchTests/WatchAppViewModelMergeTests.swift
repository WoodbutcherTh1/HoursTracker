import XCTest
import HoursTrackerKit
@testable import HoursTrackerWatch

@MainActor
final class WatchAppViewModelMergeTests: XCTestCase {
    func testPendingClockInAppliedOnTopOfPhoneSnapshot() {
        let pay = WatchPaySettings(
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
        let event = WatchClockEvent.makeClockIn(at: Date().addingTimeInterval(-1800))
        let merged = WatchAppViewModel.merge(phone: [], pending: [event], pay: pay)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, event.sessionID)
        XCTAssertTrue(merged[0].isOpen)
    }

    func testPendingClockOutClosesOpenSession() {
        let pay = WatchPaySettings(
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
        let clockIn = WatchClockEvent.makeClockIn(at: Date().addingTimeInterval(-7200))
        let open = WorkSession(
            id: clockIn.sessionID,
            date: Calendar.current.startOfDay(for: clockIn.timestamp),
            clockIn: clockIn.timestamp,
            clockOut: nil
        )
        let clockOut = WatchClockEvent.makeClockOut(
            sessionID: clockIn.sessionID,
            at: Date().addingTimeInterval(-600)
        )
        let merged = WatchAppViewModel.merge(phone: [open], pending: [clockOut], pay: pay)
        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].isOpen)
        XCTAssertEqual(merged[0].clockOut, clockOut.timestamp)
    }
}
