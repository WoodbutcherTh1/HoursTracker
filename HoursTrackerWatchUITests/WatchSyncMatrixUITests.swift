import XCTest

/// Simulator-driven taps for the manual WatchConnectivity matrix.
/// These are UI interactions against the real watch app — not kit unit tests.
final class WatchSyncMatrixUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapClockToggle() throws {
        let app = XCUIApplication()
        app.launch()
        let toggle = app.buttons["watch.clock.door"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        toggle.tap()
        // Brief settle for WCSession / local optimistic UI
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    func testUnreachableClockInQueued() throws {
        let app = XCUIApplication()
        app.launchArguments += ["HT_FORCE_WATCH_UNREACHABLE=1"]
        app.launchEnvironment["HT_FORCE_WATCH_UNREACHABLE"] = "1"
        app.launch()
        let toggle = app.buttons["watch.clock.door"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        // Ensure we clock in (label may already say Clock Out if leftover state)
        toggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    func testFlushOnly() throws {
        let app = XCUIApplication()
        // No force-unreachable: activation should flush any pending queue.
        app.launch()
        _ = app.buttons["watch.clock.door"].waitForExistence(timeout: 8)
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))
    }
}
