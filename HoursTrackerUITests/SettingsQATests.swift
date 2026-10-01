import XCTest

/// Settings reachability and the core pay fields, one assertion per test.
/// (Ported from the Mac QA suite on claude/jolly-wright-6ep32d, adapted to the app's
/// in-app language system: `-appLanguagePreference`, not `-AppleLanguages`.)
final class SettingsQATests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "UITEST_SKIP_ONBOARDING",
            "-hasSeenOnboarding.v1", "YES",
            "-appLanguagePreference", "english"
        ]
    }

    private func openSettings() {
        app.launch()
        let settingsTab = app.tabBars.firstMatch.buttons.element(boundBy: 4)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        settingsTab.tap()
        XCTAssertTrue(app.buttons["settings.save"].waitForExistence(timeout: 30), "Settings never opened")
    }

    func testRateFieldAcceptsTyping() {
        openSettings()
        let rateField = app.textFields["settings.hourlyRate"]
        XCTAssertTrue(rateField.waitForExistence(timeout: 15))
        // The Workplaces section sits above the pay fields; bring the field clear of
        // the tab bar before tapping it.
        // Short drags (a full swipe overshoots it under the navigation bar).
        let height = app.frame.height
        for _ in 0..<8 where rateField.frame.midY > height * 0.6 || rateField.frame.minY < 160 {
            let upward = rateField.frame.midY > height * 0.6
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.7 : 0.4))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.45 : 0.6))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        // The value is trailing-aligned: tap its end so the deletes clear it (a plain
        // tap can leave the caret at the start and the old value survives).
        rateField.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = rateField.value as? String ?? ""
        rateField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(current.count, 6)))
        rateField.typeText("55")
        XCTAssertEqual(rateField.value as? String, "55")
    }

    func testArrivalRemindersToggleIsReachable() {
        openSettings()
        let toggle = app.switches["settings.arrivalReminders"]
        for _ in 0..<6 where !toggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }
}
