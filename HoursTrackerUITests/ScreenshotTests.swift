import XCTest

/// App Store screenshot automation. Launches the real app in the simulator with a
/// fully fake, realistic dataset (see `ScreenshotDemoData.swift`, DEBUG-only) and
/// captures one PNG per key screen straight to `~/Desktop/AppStoreScreenshots/`.
///
/// Run from Xcode (pick a device first — screenshot pixel size follows the
/// simulator, so run once per App Store size you need, e.g. "iPhone 16 Pro Max"
/// for the 6.9" requirement) or from Terminal:
///
///   xcodebuild test \
///     -scheme HoursTracker \
///     -only-testing:HoursTrackerUITests/ScreenshotTests \
///     -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
///
/// To capture Arabic/Hebrew sets too, add `-AppleLanguages "(ar)"` (or `he`) to
/// `app.launchArguments` below and re-run — output files won't collide since the
/// name includes no language suffix, so move each language's folder aside first.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_SCREENSHOTS", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // Splash screen + seeded-data reload settle within a couple of seconds.
        Thread.sleep(forTimeInterval: 3)

        capture(app, "01_Home")

        tapTab(app, "tab.history")
        capture(app, "02_History")

        tapTab(app, "tab.export")
        capture(app, "03_Export")

        tapTab(app, "tab.settings")
        capture(app, "04_Settings")
    }

    private func tapTab(_ app: XCUIApplication, _ identifier: String) {
        let button = app.tabBars.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Tab \(identifier) never appeared")
        button.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let outDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/AppStoreScreenshots")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)

        // Also attach it to the test result, as a fallback if the direct file
        // write above is ever blocked by sandboxing on some Xcode/OS combo.
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
