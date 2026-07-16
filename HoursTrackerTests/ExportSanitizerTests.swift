import XCTest
@testable import HoursTracker

final class ExportSanitizerTests: XCTestCase {
    func testCSVNeutralizesFormulaPrefixes() {
        XCTAssertEqual(ExportSanitizer.csvCell("=cmd|' /C calc'!A0"), "'=cmd|' /C calc'!A0")
        XCTAssertTrue(ExportSanitizer.csvCell("+2+3").hasPrefix("'"))
        XCTAssertTrue(ExportSanitizer.csvCell("-2+3").hasPrefix("'"))
        XCTAssertTrue(ExportSanitizer.csvCell("@SUM(A1)").hasPrefix("'"))
        XCTAssertTrue(ExportSanitizer.csvCell("\tHI").hasPrefix("'"))
        XCTAssertTrue(ExportSanitizer.csvCell("\rHI").hasPrefix("'"))
    }

    func testCSVQuotesCommasAndQuotes() {
        XCTAssertEqual(ExportSanitizer.csvCell("a,b"), "\"a,b\"")
        XCTAssertEqual(ExportSanitizer.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testXMLEscapesQuotesAndAmpersand() {
        let escaped = ExportSanitizer.escapeXML(#"Tom & "Jerry's" <tag>"#)
        XCTAssertTrue(escaped.contains("&amp;"))
        XCTAssertTrue(escaped.contains("&quot;"))
        XCTAssertTrue(escaped.contains("&apos;"))
        XCTAssertTrue(escaped.contains("&lt;"))
        XCTAssertTrue(escaped.contains("&gt;"))
    }

    func testMarkdownEscapesPipesAndLeadingFormatters() {
        XCTAssertEqual(ExportSanitizer.markdownCell("a|b"), "a\\|b")
        XCTAssertTrue(ExportSanitizer.markdownCell("# evil").hasPrefix("\\#"))
        XCTAssertTrue(ExportSanitizer.markdownInline("- name").hasPrefix("\\-"))
        // RTL override + pipe
        let rtl = "\u{202E}bad|name"
        XCTAssertTrue(ExportSanitizer.markdownCell(rtl).contains("\\|"))
    }
}

@MainActor
final class ActivityLogCSVInjectionTests: XCTestCase {
    func testExportedCSVPrefixesHostileMessage() {
        let store = ActivityLogStore.shared
        store.wipeForPrivacy()
        defer { store.wipeForPrivacy() }

        store.log("=cmd|' /C calc'!A0", level: .info, category: "test", details: "+1+1")
        let csv = store.renderCSVForTesting()
        XCTAssertTrue(csv.contains("'=cmd|' /C calc'!A0") || csv.contains("\"'=cmd|' /C calc'!A0\""))
        XCTAssertTrue(csv.contains("'+1+1") || csv.contains("\"'+1+1\""))
    }
}
