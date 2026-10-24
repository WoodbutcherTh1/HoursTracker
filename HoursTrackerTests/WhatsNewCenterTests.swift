import XCTest
@testable import HoursTracker

@MainActor
final class WhatsNewCenterTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "whatsnew.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testFreshInstallShowsNothing() {
        let center = WhatsNewCenter(defaults: makeDefaults(), ignoresAutomatedRuns: false)
        center.evaluate(hasOnboarded: false, currentVersion: "1.10")
        XCTAssertFalse(center.showPopup)
        XCTAssertNil(center.activeRelease())
    }

    func testUpdateShowsPopupOnceAndKeepsEntryFor24Hours() {
        let defaults = makeDefaults()
        let center = WhatsNewCenter(defaults: defaults, ignoresAutomatedRuns: false)
        let start = Date()
        center.evaluate(hasOnboarded: true, now: start, currentVersion: "1.10")
        XCTAssertTrue(center.showPopup)
        center.dismissPopup()
        XCTAssertFalse(center.showPopup)
        // Same version, later the same day: no pop-up, the About entry is still there.
        center.evaluate(hasOnboarded: true, now: start.addingTimeInterval(3600), currentVersion: "1.10")
        XCTAssertFalse(center.showPopup)
        XCTAssertNotNil(center.activeRelease(now: start.addingTimeInterval(23 * 3600)))
        XCTAssertNil(center.activeRelease(now: start.addingTimeInterval(25 * 3600)))
    }

    func testVersionWithoutNotesShowsNothing() {
        let center = WhatsNewCenter(defaults: makeDefaults(), ignoresAutomatedRuns: false)
        center.evaluate(hasOnboarded: true, currentVersion: "0.0.1")
        XCTAssertFalse(center.showPopup)
    }
}
