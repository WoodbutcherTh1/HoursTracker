import XCTest
@testable import HoursTracker

final class PayslipLLMRouterTests: XCTestCase {

    // MARK: - Router fallthrough

    func testRouterFallsThroughRateLimitedProviderToLocal() async {
        let failing = StubPayslipProvider(name: "StubCloud", result: .failure(.rateLimited))
        let router = PayslipLLMRouter(providers: [
            failing,
            LocalHeuristicPayslipLLMProvider()
        ])
        let text = """
        תלוש שכר
        תקופה: 01/07/2026 - 31/07/2026
        שכר ברוטו: 15,000.00 ש\"ח
        שכר נטו: 12,345.67 ש\"ח
        """
        let result = await router.extractPayslip(ocrText: text)
        XCTAssertEqual(result.providerName, "Local")
        XCTAssertTrue(result.needsManualReview,
                      "Local fallback must always require manual review")
        XCTAssertEqual(result.fields.grossPay, 15_000.00)
        XCTAssertEqual(result.fields.netPay, 12_345.67)
    }

    func testRouterFallsThroughMissingAPIKey() async {
        let missing = StubPayslipProvider(name: "NoKey", result: .failure(.missingAPIKey))
        let router = PayslipLLMRouter(providers: [
            missing,
            LocalHeuristicPayslipLLMProvider()
        ])
        let result = await router.extractPayslip(ocrText: "שכר נטו 5,000")
        XCTAssertEqual(result.providerName, "Local")
        XCTAssertTrue(result.needsManualReview)
    }

    func testRouterReturnsCloudResultWhenSuccessful() async {
        let cloudFields = PayslipLLMFields(
            paymentMonth: "2026-07",
            grossPay: 20_000,
            netPay: 15_200,
            currency: "ILS",
            confidence: 0.9
        )
        let cloudResult = PayslipLLMStructureResult(
            fields: cloudFields,
            providerName: "StubCloud",
            rawJSON: nil,
            needsManualReview: PayslipReviewEvaluator.needsManualReview(for: cloudFields)
        )
        let cloud = StubPayslipProvider(name: "StubCloud", result: .success(cloudResult))
        let router = PayslipLLMRouter(providers: [
            cloud,
            LocalHeuristicPayslipLLMProvider()
        ])
        let result = await router.extractPayslip(ocrText: "irrelevant")
        XCTAssertEqual(result.providerName, "StubCloud")
        XCTAssertFalse(result.needsManualReview,
                       "High-confidence cloud with net + gross + month should not need review")
        XCTAssertEqual(result.fields.grossPay, 20_000)
    }

    // MARK: - Local heuristic

    func testLocalHeuristicParsesRealisticHebrewPayslip() async throws {
        let ocr = """
        חברת דוגמה בע"מ
        תלוש שכר לעובד: ישראל ישראלי
        תקופה: 01/07/2026 - 31/07/2026
        שכר ברוטו:      15,432.10 ש"ח
        ניכויים:           2,086.43
        שכר נטו:        13,345.67 ש"ח
        """
        let provider = LocalHeuristicPayslipLLMProvider()
        let result = try await provider.extractPayslip(ocrText: ocr)

        XCTAssertEqual(result.providerName, "Local")
        XCTAssertTrue(result.needsManualReview)
        XCTAssertEqual(result.fields.grossPay, 15_432.10)
        XCTAssertEqual(result.fields.netPay, 13_345.67)
        XCTAssertEqual(result.fields.payPeriodStart, "01/07/2026")
        XCTAssertEqual(result.fields.payPeriodEnd, "31/07/2026")
        XCTAssertEqual(result.fields.paymentMonth, "2026-07")
        XCTAssertEqual(result.fields.currency, "ILS")
    }

    func testLocalHeuristicHandlesEuropeanNumberFormat() {
        XCTAssertEqual(LocalHeuristicPayslipLLMProvider.parseNumber("1.234,56"), 1_234.56)
        XCTAssertEqual(LocalHeuristicPayslipLLMProvider.parseNumber("1,234.56"), 1_234.56)
        XCTAssertEqual(LocalHeuristicPayslipLLMProvider.parseNumber("1234.56"), 1_234.56)
        XCTAssertEqual(LocalHeuristicPayslipLLMProvider.parseNumber("1.234"), 1_234)
        XCTAssertEqual(LocalHeuristicPayslipLLMProvider.parseNumber("12,34"), 12.34)
        XCTAssertEqual(LocalHeuristicPayslipLLMProvider.parseNumber("500"), 500)
    }

    func testLocalHeuristicAlwaysRequiresManualReviewEvenOnHighExtraction() async throws {
        let ocr = """
        Gross Pay: 12,000.00
        Net Pay:    9,500.00
        Period: 01/06/2026 - 30/06/2026
        """
        let result = try await LocalHeuristicPayslipLLMProvider()
            .extractPayslip(ocrText: ocr)
        XCTAssertEqual(result.fields.grossPay, 12_000)
        XCTAssertEqual(result.fields.netPay, 9_500)
        XCTAssertTrue(result.needsManualReview,
                      "Local heuristic must always set needsManualReview = true")
    }

    func testLocalHeuristicOnEmptyTextStillFlagsForReview() async throws {
        let result = try await LocalHeuristicPayslipLLMProvider().extractPayslip(ocrText: "")
        XCTAssertTrue(result.needsManualReview)
        XCTAssertNil(result.fields.grossPay)
        XCTAssertNil(result.fields.netPay)
    }

    // MARK: - Review evaluation

    func testReviewEvaluatorRequiresReviewOnLowConfidence() {
        let fields = PayslipLLMFields(
            paymentMonth: "2026-07",
            grossPay: 100,
            netPay: 90,
            confidence: 0.4
        )
        XCTAssertTrue(PayslipReviewEvaluator.needsManualReview(for: fields))
    }

    func testReviewEvaluatorRequiresReviewOnMissingBothPayFields() {
        let fields = PayslipLLMFields(
            paymentMonth: "2026-07",
            confidence: 0.95
        )
        XCTAssertTrue(PayslipReviewEvaluator.needsManualReview(for: fields))
    }

    func testReviewEvaluatorRequiresReviewOnMissingPeriodAndMonth() {
        let fields = PayslipLLMFields(
            grossPay: 100,
            netPay: 80,
            confidence: 0.95
        )
        XCTAssertTrue(PayslipReviewEvaluator.needsManualReview(for: fields))
    }

    func testReviewEvaluatorPassesWhenAllPresentAndHighConfidence() {
        let fields = PayslipLLMFields(
            paymentMonth: "2026-07",
            grossPay: 100,
            netPay: 80,
            confidence: 0.9
        )
        XCTAssertFalse(PayslipReviewEvaluator.needsManualReview(for: fields))
    }

    // MARK: - Cloud request bodies (privacy — text-only)

    func testGeminiRequestBodyContainsTextOnly() throws {
        let ocr = "שכר נטו 12,345.67"
        let body = try GeminiPayslipLLMProvider.makeRequestBody(ocrText: ocr)
        XCTAssertFalse(
            PayslipCloudRequestInspector.containsBinaryAttachment(in: body),
            "Gemini payslip request must never attach image/PDF bytes"
        )
        // Confirm the top-level shape is `contents` + `generationConfig` — nothing more.
        let keys = PayslipCloudRequestInspector.topLevelKeys(in: body)
        XCTAssertEqual(keys, ["contents", "generationConfig"])
        // Confirm the OCR string actually made it into a text part.
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let contents = json?["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("שכר נטו"))
    }

    func testOpenAIRequestBodyContainsTextOnly() throws {
        let ocr = "Gross 15,000\nNet 12,000"
        let body = try OpenAICompatiblePayslipLLMProvider.makeRequestBody(
            model: "llama-3.3-70b-versatile",
            ocrText: ocr
        )
        XCTAssertFalse(
            PayslipCloudRequestInspector.containsBinaryAttachment(in: body),
            "OpenAI-compatible payslip request must never attach image/PDF bytes"
        )
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNotNil(json?["messages"])
        let messages = json?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.last?["content"] as? String, ocr)
    }

    func testInspectorDetectsAttachmentWhenPresent() throws {
        let malicious: [String: Any] = [
            "contents": [
                ["parts": [
                    ["text": "hi"],
                    ["inline_data": ["mime_type": "image/png", "data": "AAAA"]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: malicious)
        XCTAssertTrue(PayslipCloudRequestInspector.containsBinaryAttachment(in: data))
    }

    // MARK: - JSON schema decoding

    func testPayloadDecodesSnakeCaseKeysExactly() throws {
        let json = """
        {
          "pay_period_start": "01/07/2026",
          "pay_period_end":   "31/07/2026",
          "payment_month":    "2026-07",
          "gross_pay":        15000.0,
          "net_pay":          12000.5,
          "currency":         "ILS",
          "employer_name":    "Acme",
          "employee_name":    "Israel",
          "hours_regular":    182.0,
          "hours_ot":         10.5,
          "deductions_total": 3000.0,
          "confidence":       0.88,
          "notes":            "clean"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PayslipLLMPayload.self, from: json)
        XCTAssertEqual(decoded.payPeriodStart, "01/07/2026")
        XCTAssertEqual(decoded.grossPay, 15_000)
        XCTAssertEqual(decoded.netPay, 12_000.5)
        XCTAssertEqual(decoded.paymentMonth, "2026-07")
        XCTAssertEqual(decoded.currency, "ILS")
        XCTAssertEqual(decoded.confidence, 0.88)
        XCTAssertEqual(decoded.notes, "clean")
    }

    func testPayloadDecodesNotesAsArrayIntoString() throws {
        let json = #"{"gross_pay": 100, "notes": ["a", "b"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PayslipLLMPayload.self, from: json)
        XCTAssertEqual(decoded.notes, "a · b")
    }
}

private struct StubPayslipProvider: PayslipLLMProviding {
    let name: String
    let result: Result<PayslipLLMStructureResult, ScannerLLMError>

    func extractPayslip(ocrText: String) async throws -> PayslipLLMStructureResult {
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
