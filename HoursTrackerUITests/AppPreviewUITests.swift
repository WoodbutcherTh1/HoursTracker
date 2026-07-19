import XCTest

/// Drives the iPhone App Preview scenario while `record_iphone_app_preview.sh`
/// captures `simctl io … recordVideo`. Timing targets ~25s wall clock.
final class AppPreviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppPreviewScenario() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "HT_SCREENSHOT_MODE=1",
            "HT_SCREENSHOT_LANG=he",
            "-AppleLanguages", "(he)",
            "-AppleLocale", "he_IL",
        ]
        app.launchEnvironment["HT_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["HT_SCREENSHOT_LANG"] = "he"
        app.launch()

        // 0–3s: Home (clocked out) with demo data
        let clock = app.descendants(matching: .any)["phone.clock.toggle"].firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 12))
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))

        // 3–8s: Clock In → live timer
        clock.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(5.0))

        // 8–14s: History + browse days that have shifts
        tapTab(app, labels: ["היסטוריה", "History", "السجل"])
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in [1, 2, 3, 4] {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let comps = cal.dateComponents([.year, .month, .day], from: day)
            let id = String(
                format: "phone.history.day.%04d-%02d-%02d",
                comps.year ?? 0, comps.month ?? 0, comps.day ?? 0
            )
            let cell = app.descendants(matching: .any)[id].firstMatch
            if cell.waitForExistence(timeout: 1.5), cell.isHittable {
                cell.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(1.1))
            }
        }

        // 14–20s: Export — change range / format
        tapTab(app, labels: ["ייצוא", "Export", "تصدير"])
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let range = app.descendants(matching: .any)["phone.export.range"].firstMatch
        if range.waitForExistence(timeout: 3), range.isHittable {
            range.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            // Pick a visible alternate option if the wheel/menu shows it.
            let year = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "שנה")).firstMatch
            let yearEN = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Year")).firstMatch
            if year.exists { year.tap() }
            else if yearEN.exists { yearEN.tap() }
            else { app.tap() } // dismiss
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        let format = app.descendants(matching: .any)["phone.export.format"].firstMatch
        if format.waitForExistence(timeout: 2), format.isHittable {
            format.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let pdf = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "PDF")).firstMatch
            let csv = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "CSV")).firstMatch
            if csv.exists { csv.tap() }
            else if pdf.exists { pdf.tap() }
            else { app.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        } else {
            RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        }

        // 20–23s: Settings glance (national ID row is hidden in screenshot mode)
        tapTab(app, labels: ["הגדרות", "Settings", "الإعدادات"])
        RunLoop.current.run(until: Date().addingTimeInterval(2.2))
        XCTAssertTrue(
            app.descendants(matching: .any)["phone.settings.workerName"].firstMatch
                .waitForExistence(timeout: 3)
        )

        // Final 2–3s: Home hold
        tapTab(app, labels: ["בית", "Home", "الرئيسية"])
        RunLoop.current.run(until: Date().addingTimeInterval(2.8))
    }

    private func tapTab(_ app: XCUIApplication, labels: [String]) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        for label in labels {
            let button = bar.buttons[label]
            if button.waitForExistence(timeout: 1.2), button.isHittable {
                button.tap()
                return
            }
        }
        // Fallback: try any tab button whose label matches.
        for label in labels {
            let any = app.buttons[label]
            if any.exists, any.isHittable {
                any.tap()
                return
            }
        }
        XCTFail("Could not find tab among \(labels)")
    }
}
