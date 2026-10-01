import XCTest

/// App Store screenshot automation. Launches the real app in the simulator with a
/// fully fake, realistic dataset (see `ScreenshotDemoData.swift`, DEBUG-only) and
/// captures the same 5 screens (Home, Day Summary, History, Export, Settings) in
/// English, Hebrew and Arabic to
/// `~/Desktop/AppStoreScreenshots/<language>/` on the Mac.
///
/// Screenshot pixel size follows the simulator: use a 6.9" iPhone (e.g. "iPhone 16
/// Pro Max") for the App Store. Optional clean status bar first:
///
///   xcrun simctl status_bar booted override --time 9:41 --batteryState charged \
///     --batteryLevel 100 --cellularBars 4 --wifiBars 3
///
///   xcodebuild test \
///     -scheme HoursTracker \
///     -only-testing:HoursTrackerUITests/ScreenshotTests \
///     -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
final class ScreenshotTests: XCTestCase {
    /// The in-app language options (`AppLanguageOption` raw values).
    private let languages = ["english", "hebrew", "arabic"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        for language in languages {
            captureSet(language: language)
        }
    }

    private func captureSet(language: String) {
        let app = XCUIApplication()
        // A shift running for 3h25m. The language goes in both as the hook and as an
        // argument-domain default: the SwiftUI App reads it before AppDelegate runs.
        app.launchArguments += [
            "UITEST_SCREENSHOTS",
            "UITEST_CLOCKED_IN_MINUTES", "205",
            "UITEST_LANG", language,
            "-appLanguagePreference", language,
            "-hasSeenOnboarding.v1", "YES"
        ]
        // CI once showed the previous language's app (English, already clocked
        // out) instead of a fresh launch: the old process was still shutting down.
        // Make sure it is gone before launching the next language.
        if app.state != .notRunning {
            app.terminate()
        }
        _ = app.wait(for: .notRunning, timeout: 15)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not launch in \(language)")
        allowSystemPrompt()

        let clockOut = app.buttons["home.clockOut"]
        guard clockOut.waitForExistence(timeout: 30) else {
            // CI keeps no result bundle: log what is on screen instead of Home.
            print("SCREENSHOT-DEBUG \(language) state=\(app.state.rawValue):\n\(app.debugDescription.prefix(8000))")
            return XCTFail("Home (clocked in) never appeared in \(language)")
        }
        pause(3)
        capture(app, language, "01_Home")

        clockOut.tap()
        let summary = app.scrollViews["daySummary.sheet"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Day Summary never appeared in \(language)")
        pause(2)
        capture(app, language, "02_DaySummary")
        let done = app.buttons["daySummary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Day Summary has no Done button")
        done.tap()
        _ = summary.waitForNonExistence(timeout: 5)

        // Tab order is fixed: Home, History, Payslips, Export, Settings.
        for (index, name) in [(1, "03_History"), (3, "04_Export"), (4, "05_Settings")] {
            tapTab(app, index: index)
            capture(app, language, name)
        }
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 15)
    }

    /// The notification permission alert (asked on the first clock-in) belongs to
    /// SpringBoard and covers the screen until answered.
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

    private func tapTab(_ app: XCUIApplication, index: Int) {
        let button = app.tabBars.firstMatch.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Tab at index \(index) never appeared")
        button.tap()
        pause(1.5)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ app: XCUIApplication, _ language: String, _ name: String) {
        let screenshot = app.screenshot()
        // The test runner lives inside the simulator; SIMULATOR_HOST_HOME is the Mac's home.
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let outDir = URL(fileURLWithPath: home)
            .appendingPathComponent("Desktop/AppStoreScreenshots/\(language)")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))

        // Also attached to the test result, in case the direct write is ever blocked.
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
