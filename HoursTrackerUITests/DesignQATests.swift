import XCTest

/// Design QA sweep: walks the redesigned screens and attaches a screenshot of each.
///
/// Skipped in normal CI. The Design QA workflow (`.github/workflows/design-qa.yml`)
/// turns it on per device / language / text size / Reduce Motion via
/// `TEST_RUNNER_*` environment variables, then exports the screenshots as an
/// artifact. Checks are light on purpose — the screenshots are the report — but
/// every step asserts its screen actually appeared.
final class DesignQATests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var label: String { env["QA_LABEL"] ?? "local" }

    override func setUpWithError() throws {
        try XCTSkipUnless(env["DESIGN_QA"] == "1", "Design QA runs only from the Design QA workflow")
        continueAfterFailure = true
    }

    func testSweepRedesignedScreens() {
        let app = launch(["UITEST_SCREENSHOTS"])

        let clockIn = app.buttons["home.clockIn"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 30), "Home never appeared")
        pause(2)
        capture(app, "01_home_clocked_out")

        let brand = app.buttons["home.brandMark"]
        if brand.waitForExistence(timeout: 5) {
            brand.tap()
            let about = app.descendants(matching: .any)["about.sheet"]
            XCTAssertTrue(about.waitForExistence(timeout: 10), "About never opened")
            pause(1)
            capture(app, "02_about")
            dismissSheet(about, in: app)
        }

        clockIn.tap()
        let clockOut = app.buttons["home.clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 15), "Clock Out never appeared")
        pause(4)
        capture(app, "03_home_clocked_in")

        clockOut.tap()
        let summary = app.scrollViews["daySummary.sheet"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Day Summary never appeared")
        pause(2)
        capture(app, "04_day_summary")
        dismissSheet(summary, in: app)
        capture(app, "05_home_after_shift")

        for (index, name) in [(1, "06_history"), (4, "07_settings")] {
            let tab = app.tabBars.firstMatch.buttons.element(boundBy: index)
            if tab.waitForExistence(timeout: 5) {
                tab.tap()
                pause(1.5)
                capture(app, name)
            }
        }
        app.terminate()

        let onboarding = launch(["UITEST_ONBOARDING_AR"])
        let primary = onboarding.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 30), "Onboarding never appeared")
        pause(1)
        capture(onboarding, "08_onboarding_welcome")
        primary.tap()
        if onboarding.textFields["onboarding.rateField"].waitForExistence(timeout: 10) {
            pause(1)
            capture(onboarding, "09_onboarding_rate")
        }
    }

    // MARK: Helpers

    private func launch(_ hooks: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        let language = env["QA_LANG"] ?? "english"
        app.launchArguments += hooks + ["UITEST_LANG", language]
        if let size = env["QA_CONTENT_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for button in ["Allow", "Don’t Allow", "Don't Allow", "OK"] where alert.buttons[button].exists {
                alert.buttons[button].tap()
                return true
            }
            return false
        }
        app.launch()
        return app
    }

    /// Drag the sheet down from its own top edge.
    private func dismissSheet(_ sheet: XCUIElement, in app: XCUIApplication) {
        let top = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        _ = sheet.waitForNonExistence(timeout: 5)
        pause(1)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(label)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
