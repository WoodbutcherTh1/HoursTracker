import XCTest
@testable import HoursTrackerKit

final class WatchScreenshotDemoDataTests: XCTestCase {
    func testDemoSnapshotHasOpenSessionAndNoPIIFields() {
        let snap = WatchScreenshotDemoData.makeSnapshot(language: .hebrew)
        XCTAssertEqual(snap.sessions.filter(\.isOpen).count, 1)
        XCTAssertGreaterThanOrEqual(snap.sessions.filter { !$0.isOpen }.count, 3)
        XCTAssertEqual(snap.paySettings.language, .hebrew)
        XCTAssertEqual(snap.paySettings.workplaceSettingsForGrossEstimate().workerIDNumber, "")
    }
}
