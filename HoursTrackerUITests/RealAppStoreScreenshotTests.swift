import XCTest

/// Captures the three real App Store screenshots — Timer (clocked in), Graph (weekly
/// sparkline, clocked out), Calendar (History with the month grid expanded) — straight
/// from the running app, in all five store languages. These replace the HTML/CSS mockups
/// under `AppStore_Assets/Screenshots/`; raw captures land in
/// `AppStore_Assets/Raw_Screenshots/<lang>/{1,2,3}.png` on the Mac (same
/// `SIMULATOR_HOST_HOME` trick `ScreenshotTests`/`AppStoreScreenshotTests` use), sized to
/// whatever the booted simulator's screen is — use a 6.9" device (iPhone 16 Pro Max) for
/// the exact 1320×2868 App Store size.
///
///   xcodebuild test \
///     -scheme HoursTracker \
///     -only-testing:HoursTrackerUITests/RealAppStoreScreenshotTests \
///     -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
final class RealAppStoreScreenshotTests: XCTestCase {
    private let languages = ["english", "hebrew", "arabic", "russian", "thai"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureRealScreenshots() throws {
        for language in languages {
            captureSet(language: language)
        }
    }

    private func captureSet(language: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_SCREENSHOTS",
            "UITEST_CLOCKED_IN_MINUTES", "205",
            "UITEST_LANG", language,
            "-appLanguagePreference", language,
            "-hasSeenOnboarding.v1", "YES"
        ]
        if app.state != .notRunning {
            app.terminate()
        }
        _ = app.wait(for: .notRunning, timeout: 15)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not launch in \(language)")
        allowSystemPrompt()

        // 1 — Timer: clocked in, running shift + pay + weekly sparkline.
        let clockOut = app.buttons["home.clockOut"]
        guard clockOut.waitForExistence(timeout: 30) else {
            print("SCREENSHOT-DEBUG \(language) state=\(app.state.rawValue):\n\(app.debugDescription.prefix(8000))")
            return XCTFail("Home (clocked in) never appeared in \(language)")
        }
        pause(3.5)
        capture(app, language, "1")

        // 2 — Graph: clock out, Done the Day Summary sheet, land back on Home clocked out
        // (door button + rate card + the same sparkline, now the visual focus).
        clockOut.tap()
        let summary = app.scrollViews["daySummary.sheet"]
        if summary.waitForExistence(timeout: 15) {
            let done = app.buttons["daySummary.done"]
            if done.waitForExistence(timeout: 5) {
                done.tap()
                _ = summary.waitForNonExistence(timeout: 5)
            }
        }
        pause(2)
        capture(app, language, "2")

        // 3 — Calendar: History tab, full month grid expanded.
        // Tapped by position, not by accessibility identifier: right after a sheet
        // dismissal the tab bar's identifier lookup is flaky (see `ScreenshotTests.tapTab`),
        // but the tab order (Home, History, Payslips, Export, Settings) is fixed.
        let historyTab = app.tabBars.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab never appeared in \(language)")
        historyTab.tap()
        pause(1.5)
        let calendarToggle = app.descendants(matching: .any)["phone.history.calendarToggleHint"].firstMatch
        if calendarToggle.waitForExistence(timeout: 5) {
            calendarToggle.tap()
            pause(1)
        }
        capture(app, language, "3")

        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 15)
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

    private func capture(_ app: XCUIApplication, _ language: String, _ name: String) {
        let screenshot = app.screenshot()
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let outDir = URL(fileURLWithPath: home)
            .appendingPathComponent("HoursTracker-clean/AppStore_Assets/Raw_Screenshots/\(language)")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
