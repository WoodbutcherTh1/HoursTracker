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

    /// Scenario from the workflow: standard, shabbat, night, variesRateZero, newUser.
    private var scenario: String { env["QA_SCENARIO"] ?? "standard" }

    func testSweepRedesignedScreens() {
        var app = launch(["UITEST_SCREENSHOTS", "UITEST_QA_SCENARIO", scenario])

        // Shabbat / night: the seeded shift's Day Summary opens on launch.
        if scenario == "shabbat" || scenario == "night" {
            let seeded = app.scrollViews["daySummary.sheet"]
            XCTAssertTrue(seeded.waitForExistence(timeout: 30), "Seeded \(scenario) Day Summary never appeared")
            pause(2)
            capture(app, "day-summary-\(scenario)")
            seeded.swipeUp()
            pause(1)
            capture(app, "day-summary-\(scenario)-scrolled")
            closeDaySummary(app)
        }

        var clockIn = app.buttons["home.clockIn"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 30), "Home never appeared")
        pause(2)
        capture(app, "home-clocked-out")

        if scenario == "standard" {
            captureAboutAndPrivacy(app)
            // Start the shift flow from a fresh launch instead of unwinding two
            // stacked sheets (About → Privacy).
            app.terminate()
            app = launch(["UITEST_SCREENSHOTS", "UITEST_QA_SCENARIO", scenario])
            clockIn = app.buttons["home.clockIn"]
            XCTAssertTrue(clockIn.waitForExistence(timeout: 30), "Home never came back")
            pause(1)
        }

        clockIn.tap()
        let clockOut = app.buttons["home.clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 15), "Clock Out never appeared")
        pause(4)
        capture(app, "home-clocked-in")

        clockOut.tap()
        let summary = app.scrollViews["daySummary.sheet"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Day Summary never appeared")
        pause(2)
        capture(app, "day-summary")
        closeDaySummary(app)
        capture(app, "home-after-shift")

        for (index, name) in [(1, "history"), (4, "settings")] {
            let tab = app.tabBars.firstMatch.buttons.element(boundBy: index)
            if tab.waitForExistence(timeout: 5) {
                tab.tap()
                pause(1.5)
                capture(app, name)
            }
        }
        app.terminate()

        if env["QA_BACKGROUNDS"] == "1" {
            captureBackgrounds()
        }

        if scenario == "standard" || scenario == "newUser" {
            let onboarding = launch(["UITEST_ONBOARDING_AR"])
            let primary = onboarding.buttons["onboarding.primary"]
            XCTAssertTrue(primary.waitForExistence(timeout: 30), "Onboarding never appeared")
            pause(1)
            capture(onboarding, "onboarding-welcome")
            primary.tap()
            if onboarding.textFields["onboarding.rateField"].waitForExistence(timeout: 10) {
                pause(1)
                capture(onboarding, "onboarding-rate")
            }
            onboarding.terminate()
        }
    }

    private func captureAboutAndPrivacy(_ app: XCUIApplication) {
        let brand = app.buttons["home.brandMark"]
        guard brand.waitForExistence(timeout: 5) else { return XCTFail("Brand mark missing") }
        brand.tap()
        let about = app.descendants(matching: .any)["about.sheet"]
        XCTAssertTrue(about.waitForExistence(timeout: 10), "About never opened")
        pause(1)
        capture(app, "about")

        let privacyRow = app.buttons["about.privacy"]
        if privacyRow.waitForExistence(timeout: 5) {
            privacyRow.tap()
            let policy = app.scrollViews["privacy.scroll"]
            if policy.waitForExistence(timeout: 10) {
                pause(1)
                capture(app, "privacy")
                policy.swipeUp()
                policy.swipeUp()
                pause(1)
                capture(app, "privacy-scrolled")
            } else {
                XCTFail("Privacy policy never opened")
            }
        } else {
            XCTFail("Privacy row missing in About")
        }
    }

    /// Home on each of the 5 background presets (the app is dark-only, so these
    /// replace a light-mode pass).
    private func captureBackgrounds() {
        let presets = [("midnight", "0A0D0F"), ("charcoal", "121618"), ("graphite", "131313"),
                       ("slate", "0D141C"), ("onyx", "000000")]
        for (name, hex) in presets {
            let app = launch(["UITEST_SCREENSHOTS", "UITEST_BACKGROUND", hex])
            XCTAssertTrue(app.buttons["home.clockIn"].waitForExistence(timeout: 30), "Home never appeared on \(name)")
            pause(2)
            capture(app, "home-background-\(name)")
            app.terminate()
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

    /// Close the Day Summary with its Done button. A drag from the sheet's top edge
    /// is unsafe once the sheet is at full height: it starts at the top of the
    /// screen and pulls down the system Lock Screen instead.
    private func closeDaySummary(_ app: XCUIApplication) {
        let done = app.buttons["daySummary.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        } else {
            XCTFail("Day Summary has no Done button")
        }
        _ = app.scrollViews["daySummary.sheet"].waitForNonExistence(timeout: 5)
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
