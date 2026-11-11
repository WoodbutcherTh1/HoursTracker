import XCTest

/// Five clean App Store listing screenshots — Home, History, Export, Settings,
/// Account — with the seeded demo data, in English. Saved to
/// `design-qa/screenshots/` on the Mac (not just as xcresult attachments) so
/// they can be reviewed/uploaded without opening Xcode, same
/// `SIMULATOR_HOST_HOME` trick `AccessibilityQATests`/`ScreenshotTests` use.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCaptureAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_SCREENSHOTS",
            "UITEST_CLOCKED_IN_MINUTES", "205",
            "UITEST_LANG", "english",
            "-appLanguagePreference", "english",
            "-hasSeenOnboarding.v1", "YES"
        ]
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for button in ["Allow", "Don’t Allow", "Don't Allow", "OK"] where alert.buttons[button].exists {
                alert.buttons[button].tap()
                return true
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not launch")

        let clockOut = app.buttons["home.clockOut"]
        guard clockOut.waitForExistence(timeout: 30) else {
            return XCTFail("Home never appeared")
        }
        pause(3.5) // extra settle time: the weekly sparkline finishes its own async load shortly after Home appears
        save(app, "01-home")

        let historyTab = app.tabBars.firstMatch.buttons["tab.history"]
        if historyTab.waitForExistence(timeout: 10) {
            historyTab.tap()
            pause(2)
            save(app, "02-history")
        } else {
            XCTFail("History tab never appeared")
        }

        let exportTab = app.tabBars.firstMatch.buttons["tab.export"]
        if exportTab.waitForExistence(timeout: 10) {
            exportTab.tap()
            pause(2)
            save(app, "03-export")
        } else {
            XCTFail("Export tab never appeared")
        }

        let settingsTab = app.tabBars.firstMatch.buttons["tab.settings"]
        if settingsTab.waitForExistence(timeout: 10) {
            settingsTab.tap()
            pause(2)
            save(app, "04-settings")

            let account = app.buttons["settings.account"]
            if account.waitForExistence(timeout: 5) {
                account.tap()
                pause(2)
                save(app, "05-account")
            } else {
                XCTFail("Account row never appeared in Settings")
            }
        } else {
            XCTFail("Settings tab never appeared")
        }

        app.terminate()
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        // The test runner lives inside the simulator; SIMULATOR_HOST_HOME is the Mac's home.
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let outDir = URL(fileURLWithPath: home)
            .appendingPathComponent("HoursTracker-clean/design-qa/screenshots")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
