import XCTest

/// Typing Arabic-Indic digits into the onboarding rate field while the app is in
/// Arabic (RTL). The amount must read in typing order after every keystroke (no
/// digits jumping to the other side) and the field must not move.
final class OnboardingRTLUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testArabicDigitsTypeInOrderWithoutJumping() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_ONBOARDING_AR",
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_IL",
            "-AppleKeyboards", "(ar@sw=Arabic)"
        ]
        app.launch()

        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 30), "Onboarding never appeared")
        primary.tap()

        let field = app.textFields["onboarding.rateField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        let startFrame = field.frame

        var typed = ""
        for character in "٤٥٫٥" {
            field.typeText(String(character))
            typed.append(character)
            XCTAssertEqual(field.value as? String, typed, "Digits reordered after typing \(character)")
            XCTAssertEqual(field.frame.minX, startFrame.minX, accuracy: 1, "Field moved after typing \(character)")
            XCTAssertEqual(field.frame.width, startFrame.width, accuracy: 1, "Field resized after typing \(character)")
        }

        XCTAssertTrue(app.images["onboarding.rateValid"].waitForExistence(timeout: 5), "٤٥٫٥ should be a valid rate")
        XCTAssertTrue(primary.isEnabled)
    }
}
