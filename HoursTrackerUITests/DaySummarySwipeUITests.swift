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
        XCTAssertTrue(clockIn.waitForExistence(timeout: 15), "Clock In never appeared")
        clockIn.tap()
        // A permission prompt, if any, is handled by the monitor on the next interaction.

        let clockOut = app.buttons["home.clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 5), "Clock Out never appeared")
        clockOut.tap()

        let sheet = app.scrollViews["daySummary.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Day Summary never appeared")
        sheet.swipeDown(velocity: .fast)

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: sheet)
        waitForExpectations(timeout: 5)

        // Index-based, like ScreenshotTests: Home, History, Payslips, Export, Settings.
        let historyTab = app.tabBars.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(historyTab.waitForExistence(timeout: 5))
        historyTab.tap()

        let row = app.descendants(matching: .any)["history.sessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The shift is missing from History after swiping the summary away")
    }
}
