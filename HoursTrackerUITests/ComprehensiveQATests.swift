import XCTest

// MARK: - Comprehensive QA Test Suite
// Sections 2-9 + BUG#2 + BUG#3 + Color Picker + About Sheet + Break Button check
// All findings are documented via screenshots only — NO fixes.
// Screenshots land in Xcode test results (attachment lifetime = keepAlways).

final class ComprehensiveQATests: XCTestCase {

    var app: XCUIApplication!
    private let screenshotDir = "/Users/humussalad/HoursTracker-clean/design-qa/functional-test"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helper: Dismiss onboarding (3 slides)
    private func dismissOnboarding() {
        let nextPred = NSPredicate(format: "label CONTAINS 'Next' OR label CONTAINS 'التالي' OR label CONTAINS 'הבא'")
        let nextBtn = app.buttons.matching(nextPred).firstMatch
        if nextBtn.waitForExistence(timeout: 4) {
            nextBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            nextBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            // Third slide: "Start Tracking" / "ابدأ التتبع" / "התחל מעקב"
            let startPred = NSPredicate(format: "label CONTAINS 'Track' OR label CONTAINS 'ابدأ' OR label CONTAINS 'התחל' OR label CONTAINS 'Start'")
            let startBtn = app.buttons.matching(startPred).firstMatch
            if startBtn.waitForExistence(timeout: 3) {
                startBtn.tap()
            } else {
                let n3 = app.buttons.matching(nextPred).firstMatch
                if n3.exists { n3.tap() }
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: - Helper: Clock In
    private func clockIn() {
        let clockInBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock In' OR label CONTAINS 'تسجيل الدخول' OR label CONTAINS 'תיעוד כניסה'")).firstMatch
        if clockInBtn.waitForExistence(timeout: 5) {
            clockInBtn.tap()
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: - Helper: Clock Out
    private func clockOut() {
        let clockOutBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock Out' OR label CONTAINS 'تسجيل الخروج'")).firstMatch
        if clockOutBtn.waitForExistence(timeout: 5) {
            clockOutBtn.tap()
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: - Helper: Screenshot (to Xcode attachments + disk)
    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        // Attach to Xcode test results
        let att = XCTAttachment(screenshot: screenshot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        // Also save to disk
        let dir = URL(fileURLWithPath: screenshotDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    // MARK: - Helper: Scroll the Settings form until a field is reachable
    /// The Pay & Hours section sits below the fold on every device, so a field
    /// there is not queryable until the form has been scrolled.
    private func scrollToTextField(_ identifier: String, maxSwipes: Int = 6) -> XCUIElement {
        let field = app.textFields[identifier]
        for _ in 0..<maxSwipes {
            if field.exists && field.isHittable { break }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        return field
    }

    // MARK: - Helper: Normalize numerals
    /// Maps Arabic-Indic and Extended Arabic-Indic digits onto ASCII so a typed
    /// value can be asserted regardless of the locale's numeral system.
    private func asciiDigits(_ text: String) -> String {
        let map: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        return String(text.map { map[$0] ?? $0 })
    }

    // MARK: - Helper: Dump every visible text field (diagnostics)
    private func dumpTextFields(_ tag: String) {
        let fields = app.textFields.allElementsBoundByIndex
        print("[\(tag)] Total text fields visible: \(fields.count)")
        for (i, f) in fields.enumerated() {
            print("  [\(i)] id='\(f.identifier)' value='\(f.value as? String ?? "")' "
                  + "placeholder='\(f.placeholderValue ?? "")' frame=\(f.frame)")
        }
    }

    // MARK: ─────────────────────────────────────────────
    // SECTION 2 + Color Picker + About Sheet (iPhone 17 Pro English)
    // ─────────────────────────────────────────────────────
    func test02_HomeColorPickerAbout() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // ── Greeting row ──
        let greetingPred = NSPredicate(format: "label CONTAINS 'Good'")
        let greeting = app.staticTexts.matching(greetingPred).firstMatch
        print("[S2] Greeting exists: \(greeting.exists)")
        shot("s2-01-home-initial")

        // ── Brand / HoursTracker ──
        let brand = app.staticTexts["HoursTracker"]
        print("[S2] Brand visible: \(brand.exists)")

        // ── Stat cards ──
        let thisMonth = app.staticTexts["This month"].exists
        let thisWeek  = app.staticTexts["This week"].exists
        let today     = app.staticTexts["Today"].exists
        print("[S2] Stat cards — This month:\(thisMonth) This week:\(thisWeek) Today:\(today)")
        shot("s2-02-stat-cards")

        // ── WEEK CHART present? ──
        let chart = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Week' OR label CONTAINS 'week' OR label CONTAINS 'chart'")).firstMatch
        print("[S2] Week chart/sparkline element: \(chart.exists)")
        shot("s2-03-week-chart-area")

        // ── COLOR PICKER (palette icon in toolbar — accessibilityLabel = "App Theme" / "مظهر التطبيق") ──
        let palettePred = NSPredicate(format: "label CONTAINS 'Theme' OR label CONTAINS 'مظهر' OR label CONTAINS 'עיצוב' OR label CONTAINS 'palette'")
        let paletteBtn = app.buttons.matching(palettePred).firstMatch
        if paletteBtn.waitForExistence(timeout: 3) {
            print("[ColorPicker] Palette button found: \(paletteBtn.label)")
            paletteBtn.tap()
            Thread.sleep(forTimeInterval: 1)
            shot("color-picker-01-open")
            // Tap a color swatch (first circle/button in the sheet)
            let colorSwatches = app.buttons.allElementsBoundByIndex
            print("[ColorPicker] Buttons visible: \(colorSwatches.count)")
            // Try first non-toolbar button
            for i in 0..<min(colorSwatches.count, 20) {
                let b = colorSwatches[i]
                if b.frame.width < 60 && b.frame.width > 20 {
                    print("[ColorPicker] Tapping swatch at index \(i): \(b.label)")
                    b.tap()
                    Thread.sleep(forTimeInterval: 0.8)
                    shot("color-picker-02-swatch-tapped-\(i)")
                    break
                }
            }
            shot("color-picker-03-after-swatch")
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.5)
            shot("color-picker-04-dismissed")
        } else {
            print("[ColorPicker] ⚠️ Palette button NOT found in toolbar")
            // Try navigation bar
            let navBtns = app.navigationBars.buttons.allElementsBoundByIndex
            print("[ColorPicker] NavBar buttons: \(navBtns.count)")
            for b in navBtns { print("  - \(b.label)") }
            shot("color-picker-not-found")
        }

        // ── ABOUT SHEET (tap Brand mark) ──
        if brand.waitForExistence(timeout: 3) {
            print("[About] Tapping brand mark")
            brand.tap()
            Thread.sleep(forTimeInterval: 1)
            shot("about-01-sheet-open")
            // Look for version string, app name, rate link
            let versionEl = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1.' OR label CONTAINS 'Version'")).firstMatch
            print("[About] Version element: \(versionEl.exists) — '\(versionEl.label)'")
            let rateBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Rate' OR label CONTAINS 'قيّم' OR label CONTAINS 'Review'")).firstMatch
            print("[About] Rate button: \(rateBtn.exists)")
            shot("about-02-details")
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.5)
            shot("about-03-dismissed")
        }

        // ── Long press stat card (rearrange mode) ──
        let monthCard = app.staticTexts["This month"].firstMatch
        if monthCard.exists {
            monthCard.press(forDuration: 1.5)
            Thread.sleep(forTimeInterval: 1)
            shot("s2-04-rearrange-mode")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            Thread.sleep(forTimeInterval: 0.5)
            shot("s2-05-rearrange-exited")
        }
    }

    // MARK: ─────────────────────────────────────────────
    // SECTION 3 + Break Button check (iPhone 17 Pro English)
    // ─────────────────────────────────────────────────────
    func test03_ClockInBreakClockOut() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()
        shot("s3-01-before-clock-in")

        // Clock In
        let clockInBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock In'")).firstMatch
        XCTAssertTrue(clockInBtn.waitForExistence(timeout: 5), "Clock In button not found")
        print("[S3] Clock In button: '\(clockInBtn.label)'")
        clockInBtn.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("s3-02-clocked-in")

        // Check live timer elements
        let workingPred = NSPredicate(format: "label CONTAINS 'Working' OR label CONTAINS 'Since' OR label CONTAINS 'CLOCKED'")
        let workingLabel = app.staticTexts.matching(workingPred).firstMatch
        print("[S3] Clocked-in status label: \(workingLabel.exists) '\(workingLabel.label)'")

        // ── BREAK BUTTON CHECK ──
        let breakPred = NSPredicate(format: "label CONTAINS 'Break' OR label CONTAINS 'break' OR label CONTAINS 'استراحة'")
        let breakBtn = app.buttons.matching(breakPred).firstMatch
        if breakBtn.waitForExistence(timeout: 3) {
            print("[Break] ✅ Break button EXISTS: '\(breakBtn.label)'")
            shot("s3-03-break-button-exists")
            breakBtn.tap()
            Thread.sleep(forTimeInterval: 1)
            shot("s3-04-on-break")
            // Resume
            let resumePred = NSPredicate(format: "label CONTAINS[c] 'resume' OR label CONTAINS[c] 'back' OR label CONTAINS[c] 'return' OR label CONTAINS[c] 'Continue'")
            let resumeBtn = app.buttons.matching(resumePred).firstMatch
            if resumeBtn.waitForExistence(timeout: 3) {
                print("[Break] Resume button: '\(resumeBtn.label)'")
                resumeBtn.tap()
                Thread.sleep(forTimeInterval: 1)
                shot("s3-05-break-resumed")
            } else {
                print("[Break] ⚠️ Resume button not found after break")
                shot("s3-05-no-resume-button")
            }
        } else {
            print("[Break] ❌ Break button NOT found — feature not implemented")
            // Log all buttons visible
            let allBtns = app.buttons.allElementsBoundByIndex
            print("[Break] All buttons visible (\(allBtns.count)):")
            for b in allBtns { print("  '\(b.label)'") }
            shot("s3-03-no-break-button")
        }

        // Breathing animation — wait 3 seconds
        Thread.sleep(forTimeInterval: 3)
        shot("s3-06-breathing-3sec")

        // Background / Foreground
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        shot("s3-07-after-background")

        // History tab
        let historyTab = app.tabBars.buttons["History"]
        if historyTab.waitForExistence(timeout: 3) {
            historyTab.tap(); Thread.sleep(forTimeInterval: 1)
            shot("s3-08-history-while-clocked-in")
            let homeTab = app.tabBars.buttons["Home"]
            if homeTab.exists { homeTab.tap(); Thread.sleep(forTimeInterval: 1) }
            shot("s3-09-home-back-from-history")
        }

        // Clock Out
        let clockOutBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock Out'")).firstMatch
        if clockOutBtn.waitForExistence(timeout: 5) {
            print("[S3] Clock Out button found: '\(clockOutBtn.label)'")
            shot("s3-10-before-clock-out")
            clockOutBtn.tap()
            Thread.sleep(forTimeInterval: 2)
            shot("s3-11-day-summary-sheet")
        }
    }

    // MARK: ─────────────────────────────────────────────
    // SECTION 4: Day Summary Sheet
    // ─────────────────────────────────────────────────────
    func test04_DaySummary() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // Clock In then immediately Clock Out to get Day Summary
        clockIn()
        Thread.sleep(forTimeInterval: 3)
        clockOut()
        Thread.sleep(forTimeInterval: 2)

        // Sheet should be visible
        shot("s4-01-day-summary-appears")

        // Check Gross/Net hero
        let grossPred = NSPredicate(format: "label CONTAINS 'Gross' OR label CONTAINS 'Net' OR label CONTAINS 'Total'")
        let heroEl = app.staticTexts.matching(grossPred).firstMatch
        print("[S4] Hero gross/net: \(heroEl.exists) '\(heroEl.label)'")
        shot("s4-02-hero-value")

        // Gross/Net segment or button
        let grossNetPred = NSPredicate(format: "label == 'Gross' OR label == 'Net'")
        let grossBtn = app.buttons.matching(NSPredicate(format: "label == 'Gross'")).firstMatch
        let netBtn   = app.buttons.matching(NSPredicate(format: "label == 'Net'")).firstMatch
        if grossBtn.exists {
            grossBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            shot("s4-03-gross-selected")
            netBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            shot("s4-04-net-selected")
        } else {
            print("[S4] ⚠️ Gross/Net picker not found as buttons")
            shot("s4-03-no-gross-net-picker")
        }

        // Deductions section
        let deductPred = NSPredicate(format: "label CONTAINS 'Deduct' OR label CONTAINS 'Tax' OR label CONTAINS 'خصم'")
        let deductEl = app.staticTexts.matching(deductPred).firstMatch
        print("[S4] Deductions section: \(deductEl.exists)")
        if deductEl.exists { deductEl.tap(); Thread.sleep(forTimeInterval: 0.5) }
        shot("s4-05-deductions")

        // Expand sheet to .large
        let sheet = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Day' OR label CONTAINS 'Summary'")).firstMatch
        if sheet.exists {
            sheet.swipeUp(); Thread.sleep(forTimeInterval: 1)
            shot("s4-06-sheet-expanded")
        } else {
            // Try swiping up from bottom area of screen
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            Thread.sleep(forTimeInterval: 1)
            shot("s4-06-sheet-swiped-up")
        }

        // Look for Edit button
        let editBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Edit' OR label CONTAINS 'تعديل'")).firstMatch
        print("[S4] Edit button: \(editBtn.exists)")
        if editBtn.exists {
            editBtn.tap(); Thread.sleep(forTimeInterval: 1)
            shot("s4-07-edit-mode")
            // Cancel edit
            let cancelBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cancel' OR label CONTAINS 'إلغاء'")).firstMatch
            if cancelBtn.exists { cancelBtn.tap(); Thread.sleep(forTimeInterval: 0.5) }
        }
        shot("s4-08-full-sheet")

        // Delete button
        let deleteBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delete' OR label CONTAINS 'حذف'")).firstMatch
        print("[S4] Delete button: \(deleteBtn.exists)")
        shot("s4-09-delete-check")

        // Dismiss sheet
        app.swipeDown(); Thread.sleep(forTimeInterval: 1)
        shot("s4-10-sheet-dismissed")
    }

    // MARK: ─────────────────────────────────────────────
    // SECTION 6: History Tab
    // ─────────────────────────────────────────────────────
    func test06_History() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // Navigate to History tab
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 5), "History tab not found")
        historyTab.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("s6-01-history-initial")

        // Week strip
        let weekStripPred = NSPredicate(format: "label CONTAINS 'Week' OR label CONTAINS 'Mon' OR label CONTAINS 'Sun'")
        let weekEl = app.staticTexts.matching(weekStripPred).firstMatch
        print("[S6] Week strip: \(weekEl.exists)")
        shot("s6-02-week-strip")

        // Trend card
        let trendPred = NSPredicate(format: "label CONTAINS 'Trend' OR label CONTAINS 'trend' OR label CONTAINS 'Average'")
        let trendEl = app.staticTexts.matching(trendPred).firstMatch
        print("[S6] Trend card: \(trendEl.exists)")

        // Table rows (cells)
        let cells = app.cells.allElementsBoundByIndex
        print("[S6] Table cells count: \(cells.count)")
        if cells.count > 0 {
            cells[0].tap(); Thread.sleep(forTimeInterval: 1)
            shot("s6-03-shift-detail")
            app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        }
        shot("s6-04-history-table")

        // Sort button
        let sortPred = NSPredicate(format: "label CONTAINS 'Sort' OR label CONTAINS 'Filter' OR label CONTAINS 'sort'")
        let sortBtn = app.buttons.matching(sortPred).firstMatch
        print("[S6] Sort button: \(sortBtn.exists)")
        if sortBtn.exists {
            sortBtn.tap(); Thread.sleep(forTimeInterval: 1)
            shot("s6-05-sort-menu")
            app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        }

        // Month/year picker — scroll left to go back a month
        let historyView = app.otherElements.firstMatch
        historyView.swipeLeft(); Thread.sleep(forTimeInterval: 0.5)
        shot("s6-06-prev-month")
        historyView.swipeRight(); Thread.sleep(forTimeInterval: 0.5)
        shot("s6-07-current-month")
    }

    // MARK: ─────────────────────────────────────────────
    // SECTION 8: Export Tab
    // ─────────────────────────────────────────────────────
    func test08_Export() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // Export tab (index 2)
        let exportTab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(exportTab.waitForExistence(timeout: 5))
        exportTab.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("s8-01-export-initial")

        // JSON export button
        let jsonPred = NSPredicate(format: "label CONTAINS 'JSON' OR label CONTAINS 'json'")
        let jsonBtn = app.buttons.matching(jsonPred).firstMatch
        print("[S8] JSON button: \(jsonBtn.exists)")

        // CSV export button
        let csvPred = NSPredicate(format: "label CONTAINS 'CSV' OR label CONTAINS 'csv'")
        let csvBtn = app.buttons.matching(csvPred).firstMatch
        print("[S8] CSV button: \(csvBtn.exists)")
        shot("s8-02-export-options")

        if csvBtn.exists {
            csvBtn.tap(); Thread.sleep(forTimeInterval: 1.5)
            shot("s8-03-csv-share-sheet")
            // Dismiss share sheet
            app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        }
        if jsonBtn.exists {
            jsonBtn.tap(); Thread.sleep(forTimeInterval: 1.5)
            shot("s8-04-json-share-sheet")
            app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        }
        shot("s8-05-export-final")
    }

    // MARK: ─────────────────────────────────────────────
    // SECTION 9: Settings
    // ─────────────────────────────────────────────────────
    func test09_Settings() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // Settings tab (index 3)
        let settingsTab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("s9-01-settings-initial")

        // Worker info fields — addressed by identifier, not by index
        let nameField = app.textFields["settings.fullName"]
        print("[S9] Name field exists: \(nameField.exists) value: '\(nameField.value as? String ?? "n/a")'")
        shot("s9-02-worker-info")

        // Rate field — reached by its stable identifier
        let rateField = scrollToTextField("settings.hourlyRate")
        shot("s9-02b-settings-pay-section")
        dumpTextFields("S9")
        XCTAssertTrue(rateField.waitForExistence(timeout: 5), "settings.hourlyRate not reachable")
        print("[S9] Rate field frame: \(rateField.frame) hittable: \(rateField.isHittable)")
        print("[S9] Rate value before: '\(rateField.value as? String ?? "")'")
        shot("s9-03-rate-field-focused")

        rateField.clearAndEnterText("55")
        Thread.sleep(forTimeInterval: 0.6)
        shot("s9-04-rate-typed-55")

        let s9Raw = rateField.value as? String ?? ""
        print("[S9] Rate value after typing 55: '\(s9Raw)'")
        XCTAssertEqual(s9Raw, "55", "Rate field did not accept 55 — raw value was '\(s9Raw)'")

        // Scroll down to see more settings
        app.swipeUp(); Thread.sleep(forTimeInterval: 0.5)
        shot("s9-05-settings-scrolled")

        // Save button
        let savePred = NSPredicate(format: "label CONTAINS 'Save' OR label CONTAINS 'حفظ'")
        let saveBtn = app.buttons.matching(savePred).firstMatch
        print("[S9] Save button: \(saveBtn.exists)")
        if saveBtn.exists {
            saveBtn.tap(); Thread.sleep(forTimeInterval: 1)
            shot("s9-06-settings-saved")
        }

        // Arrival-reminder switch — the only notification-related toggle in
        // Settings. The old 'Notif' label probe could never match it, since the
        // toggle's label says "arrival reminders" in every language.
        let arrivalToggle = app.switches["settings.arrivalReminders"]
        print("[S9] Arrival reminders toggle: \(arrivalToggle.exists) value: '\(arrivalToggle.value as? String ?? "")'")

        // Language picker
        let langPred = NSPredicate(format: "label CONTAINS 'Language' OR label CONTAINS 'لغة'")
        let langEl = app.staticTexts.matching(langPred).firstMatch
        print("[S9] Language option: \(langEl.exists)")
        shot("s9-07-bottom-settings")
    }

    // MARK: ─────────────────────────────────────────────
    // BUG #2 + BUG #3 — iPhone SE (3rd gen)
    // Must run on SE device: A7A85567-23DA-450F-A5FC-4B6543D361E6
    // ─────────────────────────────────────────────────────
    func testBUG2_SE_ThisWeekCard() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // BUG #2: "This week" card — label "00:00" alignment on SE
        shot("bug2-01-se-home-initial")

        let thisWeek = app.staticTexts["This week"].firstMatch
        print("[BUG2] 'This week' label exists: \(thisWeek.exists)")
        if thisWeek.exists {
            print("[BUG2] 'This week' frame: \(thisWeek.frame)")
            shot("bug2-02-se-this-week-card")
        }

        // Check value label under "This week"
        let zeroPred = NSPredicate(format: "label == '00:00' OR label == '0:00'")
        let zeroLabel = app.staticTexts.matching(zeroPred).firstMatch
        print("[BUG2] '00:00' value label: \(zeroLabel.exists), frame: \(zeroLabel.frame)")
        shot("bug2-03-se-stat-cards-full")

        // Check tab bar area — does "Week total" overlap tab bar?
        let tabBar = app.tabBars.firstMatch
        print("[BUG2] Tab bar frame: \(tabBar.frame)")
        // Navigate to History to see "Week total" under tab bar
        let historyTab = app.tabBars.buttons["History"]
        if historyTab.waitForExistence(timeout: 3) {
            historyTab.tap(); Thread.sleep(forTimeInterval: 1)
            shot("bug2-04-se-history-week-total")
            let weekTotalPred = NSPredicate(format: "label CONTAINS 'Week total' OR label CONTAINS 'Total'")
            let weekTotal = app.staticTexts.matching(weekTotalPred).firstMatch
            print("[BUG2] 'Week total' element: \(weekTotal.exists) frame: \(weekTotal.frame)")
            print("[BUG2] Tab bar Y: \(tabBar.frame.minY), Week total maxY: \(weekTotal.frame.maxY)")
            if weekTotal.frame.maxY > tabBar.frame.minY {
                print("[BUG2] ❌ CONFIRMED: Week total overlaps tab bar. Overlap: \(weekTotal.frame.maxY - tabBar.frame.minY)pt")
            } else {
                print("[BUG2] ✅ Week total is above tab bar")
            }
        }
        shot("bug2-05-se-final")
    }

    func testBUG3_SE_ClockOutBelowFold() throws {
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // BUG #3: Clock Out door below fold on SE + Dynamic Type
        // First: Clock In to get clocked-in state
        clockIn()
        Thread.sleep(forTimeInterval: 2)

        shot("bug3-01-se-clocked-in")

        // Measure Clock Out button position vs screen height
        let clockOutBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Clock Out'")).firstMatch
        let screenH = app.frame.height
        print("[BUG3] Screen height: \(screenH)pt")

        if clockOutBtn.waitForExistence(timeout: 5) {
            let btnFrame = clockOutBtn.frame
            print("[BUG3] Clock Out button frame: \(btnFrame)")
            print("[BUG3] Button bottom: \(btnFrame.maxY)pt, Screen bottom: \(screenH)pt")
            if btnFrame.maxY > screenH {
                print("[BUG3] ❌ CONFIRMED: Clock Out button is BELOW FOLD by \(btnFrame.maxY - screenH)pt")
            } else if btnFrame.maxY > screenH * 0.85 {
                print("[BUG3] ⚠️ Clock Out button is in bottom 15% of screen — may be cut off with Dynamic Type")
                print("[BUG3] Button at \(Int((btnFrame.maxY / screenH) * 100))% of screen height")
            } else {
                print("[BUG3] ✅ Clock Out button is visible (\(Int((btnFrame.maxY / screenH) * 100))% screen height)")
            }
            shot("bug3-02-se-clock-out-position")
        } else {
            print("[BUG3] ❌ Clock Out button not found — trying Door button")
            let doorPred = NSPredicate(format: "label CONTAINS 'Door' OR label CONTAINS 'door'")
            let doorBtn = app.buttons.matching(doorPred).firstMatch
            print("[BUG3] Door button: \(doorBtn.exists) frame: \(doorBtn.frame)")
            shot("bug3-02-se-no-clock-out")
        }

        // Scroll to see if Clock Out is below fold
        app.swipeUp(); Thread.sleep(forTimeInterval: 0.5)
        shot("bug3-03-se-after-scroll")
        app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        shot("bug3-04-se-full-clocked-in-view")

        // Tab bar
        let tabBar = app.tabBars.firstMatch
        print("[BUG3] Tab bar frame: \(tabBar.frame)")
        shot("bug3-05-se-final")
    }

    // MARK: ─────────────────────────────────────────────
    // RTL Arabic — Sections 1-3
    // ─────────────────────────────────────────────────────
    func testRTL_Arabic_HomeClockIn() throws {
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()
        shot("rtl-ar-01-home")

        // Check greeting is RTL
        let greetPred = NSPredicate(format: "label CONTAINS 'صباح' OR label CONTAINS 'مساء' OR label CONTAINS 'Good'")
        let greet = app.staticTexts.matching(greetPred).firstMatch
        print("[RTL-AR] Greeting: \(greet.exists) '\(greet.label)'")

        // Stat cards
        shot("rtl-ar-02-stat-cards")

        // Clock In
        let ciPred = NSPredicate(format: "label CONTAINS 'Clock' OR label CONTAINS 'تسجيل' OR label CONTAINS 'دخول'")
        let ciBtn = app.buttons.matching(ciPred).firstMatch
        print("[RTL-AR] Clock In button: \(ciBtn.exists) '\(ciBtn.label)'")
        if ciBtn.waitForExistence(timeout: 5) {
            ciBtn.tap(); Thread.sleep(forTimeInterval: 2)
            shot("rtl-ar-03-clocked-in")
        }

        // Clock Out
        let coPred = NSPredicate(format: "label CONTAINS 'Clock Out' OR label CONTAINS 'خروج'")
        let coBtn = app.buttons.matching(coPred).firstMatch
        if coBtn.waitForExistence(timeout: 5) {
            coBtn.tap(); Thread.sleep(forTimeInterval: 2)
            shot("rtl-ar-04-day-summary")
        }
        app.swipeDown(); Thread.sleep(forTimeInterval: 0.5)
        shot("rtl-ar-05-final")
    }

    // MARK: ─────────────────────────────────────────────
    // Settings Rate Field — RTL Arabic (BUG #1 confirmation)
    // ─────────────────────────────────────────────────────
    func testRTL_Arabic_RateField() throws {
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        dismissOnboarding()

        // Go to Settings
        let settingsTab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap(); Thread.sleep(forTimeInterval: 1.5)
        shot("bug1-ar-01-settings")

        // Rate field by identifier. The previous label probe matched
        // "الساعات القياسية" (Standard Hours) before "الأجر بالساعة" (Hourly
        // Rate), so it measured the wrong row entirely.
        let rateField = scrollToTextField("settings.hourlyRate")
        shot("bug1-ar-02-rate-section")
        dumpTextFields("BUG1-AR")
        XCTAssertTrue(rateField.waitForExistence(timeout: 5), "settings.hourlyRate not reachable in Arabic")
        print("[BUG1-AR] Rate field frame: \(rateField.frame) hittable: \(rateField.isHittable)")
        print("[BUG1-AR] Rate value before: '\(rateField.value as? String ?? "")'")
        shot("bug1-ar-03-rate-field-default")

        rateField.clearAndEnterText("55")
        Thread.sleep(forTimeInterval: 0.6)
        shot("bug1-ar-04-rate-typed-55")

        let raw = rateField.value as? String ?? ""
        print("[BUG1-AR] Rate value after typing 55: '\(raw)' normalized: '\(asciiDigits(raw))'")
        // ar_SA renders numerals as Arabic-Indic (٥٥). Asserting on normalized
        // digits keeps a numeral-system difference from being reported as the
        // field rejecting input — those are different defects.
        XCTAssertEqual(asciiDigits(raw), "55", "Rate field did not accept 55 in Arabic — raw value was '\(raw)'")
        shot("bug1-ar-05-final")
    }
}

// clearAndEnterText is already declared in OnboardingInteractionTest.swift
