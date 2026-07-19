import XCTest
@testable import HoursTracker
import HoursTrackerKit

@MainActor
final class WatchClockEventApplyTests: XCTestCase {
    func testApplyClockInAndOutIdempotent() {
        let vm = AppViewModel(store: InMemoryStore(), locationManager: MockLocationReminderManager())
        XCTAssertTrue(vm.canClockIn)

        let clockIn = WatchClockEvent.makeClockIn(at: Date().addingTimeInterval(-7200))
        XCTAssertTrue(vm.applyWatchClockEvent(clockIn))
        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions[0].id, clockIn.sessionID)
        XCTAssertTrue(vm.isClockedIn)

        // Replay must not duplicate
        XCTAssertFalse(vm.applyWatchClockEvent(clockIn))
        XCTAssertEqual(vm.sessions.count, 1)

        let clockOut = WatchClockEvent.makeClockOut(
            sessionID: clockIn.sessionID,
            at: Date().addingTimeInterval(-600)
        )
        XCTAssertTrue(vm.applyWatchClockEvent(clockOut))
        XCTAssertFalse(vm.isClockedIn)
        XCTAssertNotNil(vm.sessions[0].clockOut)

        XCTAssertFalse(vm.applyWatchClockEvent(clockOut))
    }

    func testNonDuplicateRejectsAreLogged() {
        let log = ActivityLogStore.shared
        log.wipeForPrivacy()

        let vm = AppViewModel(store: InMemoryStore(), locationManager: MockLocationReminderManager())
        // First clock-in succeeds
        XCTAssertTrue(vm.applyWatchClockEvent(WatchClockEvent.makeClockIn()))

        // Second distinct clock-in while already open → business reject (not UUID dedupe)
        let rejectedIn = WatchClockEvent.makeClockIn()
        XCTAssertFalse(vm.applyWatchClockEvent(rejectedIn))
        XCTAssertTrue(
            log.entries.contains {
                $0.message == L10n.logEventWatchClockInRejected
                    && ($0.details ?? "").contains("already clocked in")
            }
        )

        // Clock-out with no matching open after we close, then another out → reject logged
        let openID = vm.activeSession!.id
        XCTAssertTrue(vm.applyWatchClockEvent(WatchClockEvent.makeClockOut(sessionID: openID)))
        log.wipeForPrivacy()
        XCTAssertFalse(vm.applyWatchClockEvent(WatchClockEvent.makeClockOut(sessionID: openID)))
        XCTAssertTrue(
            log.entries.contains {
                $0.message == L10n.logEventWatchClockOutRejected
                    && ($0.details ?? "").contains("no open session")
            }
        )
    }
}
