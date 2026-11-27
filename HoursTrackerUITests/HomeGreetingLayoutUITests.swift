import XCTest

/// A 30-letter Arabic or Hebrew first name at Dynamic Type XL must not push the
/// brand mark or the palette button off screen: the name truncates instead.
final class HomeGreetingLayoutUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLongArabicNameKeepsTheRowOnScreen() {
        assertRowFits(name: "عبدالرحمنالهاشميالقرشيالمكيانن", language: "arabic")
    }

    func testLongHebrewNameKeepsTheRowOnScreen() {
        assertRowFits(name: "אברהםיצחקיעקבמשהאהרןדודשלמהאלה", language: "hebrew")
    }

    private func assertRowFits(name: String, language: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(name.count, 30, "Test name must be 30 letters", file: file, line: line)

        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_HOME_NAME", name, language,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"
        ]
        app.launch()

        let brand = app.buttons["home.brandMark"]
        let palette = app.buttons["home.themeButton"]
        XCTAssertTrue(brand.waitForExistence(timeout: 30), "Brand mark never appeared", file: file, line: line)
        XCTAssertTrue(palette.waitForExistence(timeout: 5), "Palette button never appeared", file: file, line: line)

        let screen = app.windows.firstMatch.frame
        for (label, element) in [("brand mark", brand), ("palette", palette)] {
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX, "\(label) spills off the leading edge", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX, "\(label) spills off the trailing edge", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(label) lost its 44pt touch target", file: file, line: line)
        }
        XCTAssertFalse(brand.frame.intersects(palette.frame), "Brand mark and palette overlap", file: file, line: line)
    }

    /// Reported symptom: with a real (non-empty) account — an open shift, a week of
    /// sparkline data — tapping Settings then Export causes a multi-second main-thread
    /// hang with the tab bar glitching. A blank/guest account never triggers it. Seeds
    /// realistic data via `UITEST_SCREENSHOTS` (open shift, hourly rate, week hours —
    /// see `ScreenshotDemoData`) and times each tab switch; a real hang shows up as a
    /// `tap()` call that takes far longer than the others, not just a flaky wait.
    func testTabSwitchingWithSeededDataDoesNotHang() {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_SCREENSHOTS", "UITEST_LANG", "english"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Tab bar never appeared")
        let settingsTab = tabBar.buttons.element(boundBy: 4)
        let exportTab = tabBar.buttons.element(boundBy: 3)
        let homeTab = tabBar.buttons.element(boundBy: 0)

        var worst: (label: String, seconds: Double) = ("", 0)
        for round in 0..<6 {
            let (tab, label) = round.isMultiple(of: 2) ? (settingsTab, "settings") : (exportTab, "export")
            let start = Date().timeIntervalSinceReferenceDate
            tab.tap()
            _ = app.wait(for: .runningForeground, timeout: 15)
            let elapsed = Date().timeIntervalSinceReferenceDate - start
            if elapsed > worst.seconds { worst = (label, elapsed) }
            // Round 0 (first navigation after cold launch) has its own one-time
            // overhead — first view construction, XCUITest's own idle-settling —
            // seen up to ~4.4s on a disk-pressured host even on main unmodified.
            // The reported bug is 6000-9000ms and repeats on every tap, so the
            // threshold only needs to separate "that" from ordinary variance.
            XCTAssertLessThan(elapsed, 6.0, "Switching to \(label) (round \(round)) took \(elapsed)s — looks like the reported main-thread hang")
        }
        homeTab.tap()
        XCTAssertEqual(app.state, .runningForeground, "App did not survive repeated Settings/Export tab switching with seeded data")
        print("SLOWEST SWITCH: \(worst.label) took \(worst.seconds)s")
    }
}
