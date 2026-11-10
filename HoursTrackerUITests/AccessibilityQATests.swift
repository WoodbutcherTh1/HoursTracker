import XCTest

/// Accessibility QA sweep for the views touched by the VoiceOver / Dynamic Type
/// pass: the Home live timer + door + weekly chart, and History's monthly trend
/// chart. Captures each at the default text size and at the largest
/// accessibility Dynamic Type size, so a layout regression at either extreme is
/// visible without a device in hand. Screenshots land on the Mac's filesystem
/// (not just as xcresult attachments) so they can be reviewed outside Xcode —
/// same `SIMULATOR_HOST_HOME` trick `ScreenshotTests` already uses.
final class AccessibilityQATests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCaptureAccessibilitySweep() {
        capture(contentSize: nil, label: "default")
        capture(contentSize: "UICTContentSizeCategoryAccessibilityXXXL", label: "ax-xxxl")
    }

    private func capture(contentSize: String?, label: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_SCREENSHOTS",
            "UITEST_LANG", "english",
            "-appLanguagePreference", "english",
            "-hasSeenOnboarding.v1", "YES"
        ]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for button in ["Allow", "Don’t Allow", "Don't Allow", "OK"] where alert.buttons[button].exists {
                alert.buttons[button].tap()
                return true
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not launch (\(label))")

        let clockIn = app.buttons["home.clockIn"]
        guard clockIn.waitForExistence(timeout: 30) else {
            return XCTFail("Home never appeared (\(label))")
        }
        pause(1.5)
        save(app, label, "01-home-clockedout")

        // Clock in: the live timer + the weekly sparkline chart both become visible.
        clockIn.tap()
        allowSystemPrompt()
        let clockOut = app.buttons["home.clockOut"]
        if clockOut.waitForExistence(timeout: 15) {
            pause(3)
            save(app, label, "02-home-clockedin-timer-door-chart")
        } else {
            XCTFail("Clock Out never appeared after clocking in (\(label))")
        }

        // History's monthly trend chart (Swift Charts bars with the new per-mark
        // accessibility labels).
        let historyTab = app.tabBars.firstMatch.buttons["tab.history"]
        if historyTab.waitForExistence(timeout: 10) {
            historyTab.tap()
            pause(2)
            save(app, label, "03-history-monthly-trend-chart")
        } else {
            XCTFail("History tab never appeared (\(label))")
        }

        app.terminate()
    }

    private func allowSystemPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func save(_ app: XCUIApplication, _ label: String, _ name: String) {
        let screenshot = app.screenshot()
        // The test runner lives inside the simulator; SIMULATOR_HOST_HOME is the Mac's home.
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let outDir = URL(fileURLWithPath: home)
            .appendingPathComponent("HoursTracker-clean/design-qa/accessibility")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(label)__\(name).png"))

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(label)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
