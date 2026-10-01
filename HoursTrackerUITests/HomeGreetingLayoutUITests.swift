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
}
