import Foundation

/// Calls Google Gemini `generateContent` for structured payslip extraction.
///
/// The request body carries **text only** — the raw OCR string. Image / PDF bytes must
/// never be attached here, so the tests that assert on the request body can verify the
/// scanner pipeline hands the LLM sanitised OCR only.
struct GeminiPayslipLLMProvider: PayslipLLMProviding {
    let name = "Gemini"
    private let apiKey: String?
    private let model: String
    private let session: URLSession

    init(
        apiKey: String? = KeychainStore.string(for: .geminiAPIKey),
        model: String = "gemini-2.5-flash",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func extractPayslip(ocrText: String) async throws -> PayslipLLMStructureResult {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScannerLLMError.missingAPIKey
        }

        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ScannerLLMError.emptyResult
        }

        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw ScannerLLMError.invalidResponse("bad URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        request.httpBody = try Self.makeRequestBody(ocrText: trimmed)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ScannerLLMError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                break
            case 429:
                throw ScannerLLMError.rateLimited
            case 403, 404:
                throw ScannerLLMError.quotaExceeded
            default:
                let snippet = String(data: data, encoding: .utf8) ?? ""
                if snippet.localizedCaseInsensitiveContains("quota") {
                    throw ScannerLLMError.quotaExceeded
                }
                throw ScannerLLMError.network("HTTP \(http.statusCode)")
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw ScannerLLMError.invalidResponse("missing candidates")
        }

        let jsonText = GeminiScannerLLMProvider.extractJSONObject(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw ScannerLLMError.invalidResponse("empty JSON")
        }

        do {
            let payload = try JSONDecoder().decode(PayslipLLMPayload.self, from: jsonData)
            return PayslipLLMStructureResult(
                fields: payload,
                providerName: name,
                rawJSON: jsonText,
                needsManualReview: PayslipReviewEvaluator.needsManualReview(for: payload)
            )
        } catch {
            throw ScannerLLMError.invalidResponse(error.localizedDescription)
        }
    }

    /// Testable request-body builder. Guarantees the payload contains **only** the OCR
    /// prompt string — never image or PDF bytes.
    static func makeRequestBody(ocrText: String) throws -> Data {
        let prompt = buildPrompt(ocrText: String(ocrText.prefix(12_000)))
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Prompt shared with the OpenAI-compatible provider so the two cloud paths return
    /// exactly the same schema. Vocabulary covers Hebrew, English and Arabic.
    static func buildPrompt(ocrText: String) -> String {
        """
        You extract payslip data from noisy OCR text (Hebrew, English or Arabic).

        Return ONLY valid JSON matching this exact schema — no markdown, no commentary:
        {
          "pay_period_start": "DD/MM/YYYY | null",
          "pay_period_end":   "DD/MM/YYYY | null",
          "payment_month":    "YYYY-MM | null",
          "gross_pay":        0.0,
          "net_pay":          0.0,
          "currency":         "ILS | USD | EUR | null",
          "employer_name":    "string | null",
          "employee_name":    "string | null",
          "hours_regular":    0.0,
          "hours_ot":         0.0,
          "deductions_total": 0.0,
          "confidence":       0.0,
          "notes":            "short free text | null"
        }

        Vocabulary hints:
        - Hebrew: שכר ברוטו / ברוטו = gross_pay; שכר נטו / נטו = net_pay; תקופה = period.
        - English: Gross / Gross Pay = gross_pay; Net / Net Pay / Take Home = net_pay.
        - Arabic: صافي = net_pay; إجمالي / الراتب الإجمالي = gross_pay.

        Rules:
        - NEVER invent monetary amounts. If a value is not clearly present, use null and
          lower the confidence.
        - Numbers may be formatted as 1,234.56 or 1.234,56 or 1234.56 — normalise to a plain
          number (dot as decimal separator, no thousands separators).
        - `payment_month` is the calendar month the payslip pays for, formatted YYYY-MM.
        - Dates should be DD/MM/YYYY (day first) when order is ambiguous.
        - `confidence` is 0..1. Use < 0.6 when several key fields are unclear.

        OCR:
        \(ocrText)
        """
    }
}
