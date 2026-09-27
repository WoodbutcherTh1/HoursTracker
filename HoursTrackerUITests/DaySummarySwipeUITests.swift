import XCTest

/// Swiping the Day Summary away must never lose the shift: Clock In → Clock Out →
/// swipe the summary down → History still lists the shift.
final class DaySummarySwipeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSwipingSummaryAwayKeepsTheShift() {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_DAY_SUMMARY", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Clocking in can raise a system permission prompt (notifications) — dismiss it
        // either way; the test is about the shift, not the permission.
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for label in ["Allow", "Don’t Allow", "Don't Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()

        let clockIn = app.buttons["home.clockIn"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 30), "Clock In never appeared")
        clockIn.tap()
        // A permission prompt, if any, is handled by the monitor on the next interaction.

        let clockOut = app.buttons["home.clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 15), "Clock Out never appeared")
        clockOut.tap()

        let sheet = app.scrollViews["daySummary.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "Day Summary never appeared")

        // Drag the sheet down from its top edge (the grabber area) — a swipe inside
        // the scroll view can be taken as a scroll instead of a dismiss. One retry,
        // since a slow runner can start the drag before the sheet has settled.
        for attempt in 1...2 where sheet.exists {
            let top = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            top.press(forDuration: 0.1, thenDragTo: bottom)
            if attempt == 1 { _ = sheet.waitForNonExistence(timeout: 5) }
        }

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "The Day Summary did not close on swipe down")

        // Index-based, like ScreenshotTests: Home, History, Payslips, Export, Settings.
        let historyTab = app.tabBars.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10))
        historyTab.tap()

        let row = app.descendants(matching: .any)["history.sessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The shift is missing from History after swiping the summary away")
    }
}
