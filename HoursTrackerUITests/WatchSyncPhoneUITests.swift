import XCTest

/// Phone-side UI taps for the Watch sync manual matrix.
final class WatchSyncPhoneUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhoneClockIn() throws {
        let app = XCUIApplication()
        app.launch()
        let toggle = app.descendants(matching: .any)["phone.clock.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }
}
