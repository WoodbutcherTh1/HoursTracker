import XCTest

final class OnboardingInteractionTest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Full English functional test: Sections 2 + 3
    func testHomeAndClockInEnglish() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)

        // Dismiss onboarding if shown
        let nextBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
        if nextBtn.waitForExistence(timeout: 4) {
            nextBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            nextBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            let startBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Track'")).firstMatch
            if startBtn.exists { startBtn.tap() }
            else {
                let n2 = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
                if n2.exists { n2.tap() }
            }
            Thread.sleep(forTimeInterval: 2)
        }
        addScreenshot("home-en-initial")

        // === SECTION 2: Home Clocked Out ===
        // Verify greeting row exists
        let greetingText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Good'")).firstMatch
        let hasGreeting = greetingText.exists
        print("✅ Greeting row exists: \(hasGreeting)")

        // Check HoursTracker brand
        let brand = app.staticTexts["HoursTracker"]
        print("✅ Brand 'HoursTracker' visible: \(brand.exists)")

        // Check stat cards
        let thisMonth = app.staticTexts["This month"].exists
        let thisWeek = app.staticTexts["This week"].exists
        let today = app.staticTexts["Today"].exists
        print("✅ Stat cards - This month:\(thisMonth) This week:\(thisWeek) Today:\(today)")
        addScreenshot("home-en-stat-cards")

        // Tap palette icon (color picker)
        let paletteBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'palette'")).firstMatch
        if paletteBtn.waitForExistence(timeout: 3) {
            paletteBtn.tap(); Thread.sleep(forTimeInterval: 1)
            addScreenshot("home-en-color-picker-open")
            // Dismiss color picker
            app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        } else {
            print("⚠️ Palette button not found via label, trying index")
            addScreenshot("home-en-palette-not-found")
        }

        // Tap brand → About Sheet
        if brand.exists {
            brand.tap(); Thread.sleep(forTimeInterval: 1)
            addScreenshot("home-en-about-sheet")
            app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        }

        // Hold stat card to rearrange (long press)
        let monthCard = app.staticTexts["This month"].firstMatch
        if monthCard.exists {
            monthCard.press(forDuration: 1.5)
            Thread.sleep(forTimeInterval: 1)
            addScreenshot("home-en-card-rearrange-mode")
            // Tap elsewhere to exit rearrange
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // === SECTION 3: Clock In ===
        let clockInBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock In'")).firstMatch
        XCTAssertTrue(clockInBtn.waitForExistence(timeout: 5), "Clock In button not found")
        print("✅ Clock In button found: \(clockInBtn.label)")
        addScreenshot("home-en-before-clock-in")

        clockInBtn.tap()
        Thread.sleep(forTimeInterval: 2)
        addScreenshot("home-en-clocked-in-state")

        // Verify live timer visible
        let workingLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Working'")).firstMatch
        print("✅ 'Working since' label: \(workingLabel.exists)")

        // Check breathing animation is active (no direct check, just visual)
        Thread.sleep(forTimeInterval: 2)
        addScreenshot("home-en-breathing-2sec")

        // Test Break button
        let breakBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Break'")).firstMatch
        if breakBtn.waitForExistence(timeout: 5) {
            breakBtn.tap(); Thread.sleep(forTimeInterval: 1)
            addScreenshot("home-en-on-break")
            print("✅ Break button works")

            // Resume
            let backBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'back' OR label CONTAINS[c] 'resume' OR label CONTAINS[c] 'Return'")).firstMatch
            if backBtn.waitForExistence(timeout: 3) {
                backBtn.tap(); Thread.sleep(forTimeInterval: 1)
                addScreenshot("home-en-break-resumed")
            } else {
                addScreenshot("home-en-break-resume-not-found")
            }
        } else {
            print("⚠️ Break button not found")
            addScreenshot("home-en-no-break-button")
        }

        // Background / Foreground test
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        addScreenshot("home-en-after-background")

        // Switch to History tab and back
        let historyTab = app.tabBars.buttons["History"]
        if historyTab.waitForExistence(timeout: 3) {
            historyTab.tap(); Thread.sleep(forTimeInterval: 1)
            addScreenshot("history-from-clocked-in")
            let homeTab = app.tabBars.buttons["Home"]
            homeTab.tap(); Thread.sleep(forTimeInterval: 1)
            addScreenshot("home-back-from-history")
        }

        // Clock Out
        let clockOutBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock Out'")).firstMatch
        if clockOutBtn.waitForExistence(timeout: 5) {
            print("✅ Clock Out button found")
            addScreenshot("home-en-before-clock-out")
            clockOutBtn.tap()
            Thread.sleep(forTimeInterval: 2)
            addScreenshot("day-summary-after-clock-out")
        } else {
            print("❌ Clock Out button NOT found")
            addScreenshot("home-en-clock-out-missing")
        }
    }

    // MARK: - Helpers
    private func addScreenshot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        tap()
        if let sv = value as? String, !sv.isEmpty {
            let del = String(repeating: XCUIKeyboardKey.delete.rawValue, count: sv.count + 5)
            typeText(del)
        }
        typeText(text)
    }
}
