import UIKit
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
        // BUG #1: the value was stored but never drawn in RTL. Check the pixels.
        XCTAssertGreaterThan(Self.textPixelCount(in: field), 200, "Typed digits are not drawn in Arabic")
    }

    /// Hebrew, Western digits: typed "50" must be visible, not only stored.
    func testHebrewDigitsAreDrawn() {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_ONBOARDING_AR", "UITEST_LANG", "hebrew",
            "-appLanguagePreference", "hebrew", "-hasSeenOnboarding.v1", "NO"
        ]
        app.launch()

        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 30), "Onboarding never appeared")
        primary.tap()
        let field = app.textFields["onboarding.rateField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        let empty = Self.textPixelCount(in: field)
        field.typeText("50")
        XCTAssertEqual(field.value as? String, "50")
        XCTAssertGreaterThan(Self.textPixelCount(in: field), empty + 200, "Typed digits are not drawn in Hebrew")
    }

    /// Near-white pixels (the text colour) in a screenshot of `element`. The caret,
    /// border and ✓ are accent/green and the placeholder is grey, so an empty field
    /// counts ~0 and a drawn number counts thousands.
    private static func textPixelCount(in element: XCUIElement) -> Int {
        guard let image = element.screenshot().image.cgImage else { return 0 }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4)
        where pixels[index] > 220 && pixels[index + 1] > 220 && pixels[index + 2] > 220 {
            count += 1
        }
        return count
    }
}
