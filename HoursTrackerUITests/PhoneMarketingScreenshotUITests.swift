import XCTest

/// Captures raw iPhone App Store screenshots in `HT_SCREENSHOT_MODE` demo data.
/// Output folder comes from env `HT_PHONE_SCREENSHOT_OUT` (absolute path).
final class PhoneMarketingScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureMarketingScreens() throws {
        // Shell script writes /tmp/ht-phone-screenshot-config.json (env vars don't reach UITest host).
        let configURL = URL(fileURLWithPath: "/tmp/ht-phone-screenshot-config.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Invalid screenshot config JSON")

        let outRoot = (json?["output"] as? String) ?? ""
        XCTAssertFalse(outRoot.isEmpty, "config.output required")

        let lang = (json?["lang"] as? String) ?? "en"
        let slotFilter = (json?["slots"] as? String) ?? "home,history,export,settings"
        let slots = Set(slotFilter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let sizeFolder = (json?["sizeFolder"] as? String) ?? "6.9-1320x2868"

        let dest = URL(fileURLWithPath: outRoot)
            .appendingPathComponent(sizeFolder)
            .appendingPathComponent(lang)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        func launch(homeActive: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            // Use ar (not ar_SA): ar_SA makes Calendar.current Islamic/Umm al-Qura and
            // breaks Gregorian payroll windows / History totals in marketing captures.
            let appleLang = lang == "he" ? "he" : lang == "ar" ? "ar" : "en"
            let appleLocale = lang == "he" ? "he_IL" : lang == "ar" ? "ar" : "en_US"
            app.launchArguments = [
                "HT_SCREENSHOT_MODE=1",
                "HT_SCREENSHOT_LANG=\(lang)",
                "-AppleLanguages", "(\(appleLang))",
                "-AppleLocale", appleLocale,
            ]
            if homeActive {
                app.launchArguments.append("HT_SCREENSHOT_HOME_ACTIVE=1")
                app.launchEnvironment["HT_SCREENSHOT_HOME_ACTIVE"] = "1"
            }
            app.launchEnvironment["HT_SCREENSHOT_MODE"] = "1"
            app.launchEnvironment["HT_SCREENSHOT_LANG"] = lang
            // Prefer dark UI in the process as well (app also forces preferredColorScheme).
            app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
            app.launch()
            return app
        }

        func waitReady(_ app: XCUIApplication) {
            let clock = app.descendants(matching: .any)["phone.clock.toggle"].firstMatch
            XCTAssertTrue(clock.waitForExistence(timeout: 15))
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        func saveScreenshot(_ app: XCUIApplication, name: String) throws {
            let shot = app.screenshot()
            let url = dest.appendingPathComponent("\(name).png")
            try shot.pngRepresentation.write(to: url)
            // Dimension note is validated later by the compose script / capture shell.
            print("Wrote \(url.path)")
        }

        func tapTab(_ app: XCUIApplication, labels: [String]) {
            let bar = app.tabBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            for label in labels {
                let button = bar.buttons[label]
                if button.waitForExistence(timeout: 1.0), button.isHittable {
                    button.tap()
                    return
                }
            }
            XCTFail("Missing tab among \(labels)")
        }

        // Home — clocked in (active shift)
        if slots.contains("home") {
            let app = launch(homeActive: true)
            waitReady(app)
            try saveScreenshot(app, name: "01-home")
            app.terminate()
        }

        // Remaining tabs share one launch (clocked out is fine; history still has shifts)
        if slots.contains("history") || slots.contains("export") || slots.contains("settings") {
            let app = launch(homeActive: false)
            waitReady(app)

            if slots.contains("history") {
                tapTab(app, labels: ["היסטוריה", "History", "السجل"])
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                // Screenshot mode lists ~3 weeks of shifts; keep week strip on the
                // primary demo day (−1) so the calendar looks populated.
                let cal = Calendar.current
                let focusDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
                let c = cal.dateComponents([.year, .month, .day], from: focusDay)
                let id = String(format: "phone.history.day.%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
                let cell = app.descendants(matching: .any)[id].firstMatch
                if cell.waitForExistence(timeout: 2), cell.isHittable {
                    cell.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                }
                try saveScreenshot(app, name: "02-history")
            }

            if slots.contains("export") {
                tapTab(app, labels: ["ייצוא", "Export", "تصدير"])
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                try saveScreenshot(app, name: "03-export")
            }

            if slots.contains("settings") {
                tapTab(app, labels: ["הגדרות", "Settings", "الإعدادات"])
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                // Scroll until tax/pay rules are visible — stop there so location
                // chrome does not peek under the floating tab bar.
                let tax = app.descendants(matching: .any)["phone.settings.tax"].firstMatch
                for _ in 0..<8 {
                    if tax.exists, tax.isHittable { break }
                    app.swipeUp()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                }
                _ = tax.waitForExistence(timeout: 2)
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                try saveScreenshot(app, name: "04-settings")
            }
            app.terminate()
        }
    }
}
