import XCTest
@testable import HoursTracker

final class ScannerLLMRouterTests: XCTestCase {
    func testFallsThroughRateLimitedProviderToLocal() async {
        let failing = StubScannerLLMProvider(
            name: "StubCloud",
            error: .rateLimited
        )
        let router = ScannerLLMRouter(providers: [
            failing,
            LocalHeuristicScannerLLMProvider()
        ])
        let text = "12/07/2026 08:00 17:00"
        let result = await router.structure(ocrText: text)
        XCTAssertEqual(result.providerName, "Local")
        XCTAssertFalse(result.rows.isEmpty)
    }

    func testMissingKeyFallsThrough() async {
        let missing = StubScannerLLMProvider(
            name: "NoKey",
            error: .missingAPIKey
        )
        let router = ScannerLLMRouter(providers: [
            missing,
            LocalHeuristicScannerLLMProvider()
        ])
        let result = await router.structure(ocrText: "12/07/2026 09:00 18:00")
        XCTAssertEqual(result.providerName, "Local")
    }
}

private struct StubScannerLLMProvider: ScannerLLMProviding {
    let name: String
    let error: ScannerLLMError

    func structure(ocrText: String) async throws -> ScannerLLMStructureResult {
        throw error
    }
}

final class GeminiJSONExtractTests: XCTestCase {
    func testStripsMarkdownFence() {
        let raw = """
        ```json
        {"rows":[]}
        ```
        """
        let extracted = GeminiScannerLLMProvider.extractJSONObject(from: raw)
        XCTAssertTrue(extracted.hasPrefix("{"))
        XCTAssertTrue(extracted.contains("\"rows\""))
    }
}
