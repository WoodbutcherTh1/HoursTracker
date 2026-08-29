import XCTest
@testable import HoursTracker

/// The plan is the only thing that crosses back from the network into the app, so its
/// decoding is the boundary that has to hold: anything a model can emit must either
/// become a well-formed plan or be refused.
final class AssistantPlanTests: XCTestCase {
    func testDecodesAFullPlan() throws {
        let json = """
        {"action":"aggregate_pay","pay_mode":"gross","filters":{"month":"2026-07",\
        "clock_in_after":"17:00","overtime_tier":"ot125"}}
        """
        let plan = try AssistantPlan.decode(from: json)

        XCTAssertEqual(plan.action, .aggregatePay)
        XCTAssertEqual(plan.payMode, .gross)
        XCTAssertEqual(plan.filters.month, "2026-07")
        XCTAssertEqual(plan.filters.clockInAfter, "17:00")
        XCTAssertEqual(plan.filters.overtimeTier, .ot125)
    }

    func testStripsMarkdownFencesSomeModelsStillEmit() throws {
        let json = """
        ```json
        {"action":"summarize_hours","filters":{"month":"2026-08"}}
        ```
        """
        let plan = try AssistantPlan.decode(from: json)

        XCTAssertEqual(plan.action, .summarizeHours)
        XCTAssertEqual(plan.filters.month, "2026-08")
    }

    /// A model inventing a capability must not produce an error the user sees as a bug —
    /// it is simply out of scope.
    func testUnknownActionBecomesOutOfScope() throws {
        let plan = try AssistantPlan.decode(from: #"{"action":"book_flight"}"#)
        XCTAssertEqual(plan.action, .outOfScope)
    }

    func testMissingActionBecomesOutOfScope() throws {
        let plan = try AssistantPlan.decode(from: #"{"filters":{"month":"2026-08"}}"#)
        XCTAssertEqual(plan.action, .outOfScope)
    }

    func testEmptyAndNullFiltersAreDropped() throws {
        let json = """
        {"action":"list_sessions","filters":{"month":"","start_date":null,\
        "overtime_tier":"125","day_type":"  "}}
        """
        let plan = try AssistantPlan.decode(from: json)

        XCTAssertTrue(plan.filters.isEmpty)
        XCTAssertNil(plan.filters.overtimeTier, "an unrecognized tier should drop, not throw")
    }

    func testGarbageIsRejectedRatherThanGuessedAt() {
        XCTAssertThrowsError(try AssistantPlan.decode(from: "sorry, I can't help with that"))
    }

    func testDocumentFormatMapsOntoTheAppsExportFormats() throws {
        let plan = try AssistantPlan.decode(
            from: #"{"action":"generate_document","document_format":"word"}"#
        )
        XCTAssertEqual(plan.documentFormat, .word)
        XCTAssertEqual(plan.documentFormat?.exportFormat, .docx)
    }
}
