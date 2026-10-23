import XCTest

/// Captures the screens used in the launch videos (Home, History, Payslips, Export,
/// Settings, Account, Assistant) in English, Hebrew and Arabic, with the demo data.
/// Files land in ~/Desktop/AppStoreScreenshots/<language>/mNN_<name>.png on the Mac.
///
///   xcodebuild test -scheme HoursTracker \
///     -only-testing:HoursTrackerUITests/MarketingShotsTests
final class MarketingShotsTests: XCTestCase {
    private let languages = ProcessInfo.processInfo.environment["MKT_LANGS"]?.components(separatedBy: ",") ?? ["english", "hebrew", "arabic"]

    override func setUp() {
        continueAfterFailure = true
    }

    func testCaptureMarketingShots() throws {
        for language in languages {
            captureSet(language)
        }
    }

    private func captureSet(_ language: String) {
        // Clocked out: Home with the green door.
        var app = launch(language, clockedIn: false)
        pause(3)
        capture(app, language, "m01_home_out")
        finish(app)

        // Clocked in: Home, then every tab.
        app = launch(language, clockedIn: true)
        _ = app.buttons["home.clockOut"].waitForExistence(timeout: 30)
        pause(3)
        capture(app, language, "m02_home_in")
        for (index, name) in [(1, "m03_history"), (2, "m04_payslips"), (3, "m05_export"), (4, "m06_settings")] {
            tapTab(app, index: index)
            capture(app, language, name)
        }
        let account = app.buttons["settings.account"]
        if account.waitForExistence(timeout: 5) {
            account.tap()
            pause(2)
            capture(app, language, "m07_account")
        }
        finish(app)

        // Assistant, opened from Home.
        app = launch(language, clockedIn: true)
        let assistant = app.buttons["assistant.open"].firstMatch
        if assistant.waitForExistence(timeout: 20) {
            assistant.tap()
            pause(2.5)
            capture(app, language, "m08_assistant")
        }
        finish(app)
    }

    private func launch(_ language: String, clockedIn: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_SCREENSHOTS", "UITEST_LANG", language,
                                "-appLanguagePreference", language, "-hasSeenOnboarding.v1", "YES"]
        if clockedIn {
            app.launchArguments += ["UITEST_CLOCKED_IN_MINUTES", "205"]
        }
        if app.state != .notRunning { app.terminate() }
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        allowSystemPrompt()
        return app
    }

    private func finish(_ app: XCUIApplication) {
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

    private func tapTab(_ app: XCUIApplication, index: Int) {
        let button = app.tabBars.firstMatch.buttons.element(boundBy: index)
        guard button.waitForExistence(timeout: 5) else { return }
        button.tap()
        pause(2)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ app: XCUIApplication, _ language: String, _ name: String) {
        let screenshot = app.screenshot()
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let outDir = URL(fileURLWithPath: home).appendingPathComponent("Desktop/AppStoreScreenshots/\(language)")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
