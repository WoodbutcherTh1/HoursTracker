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

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ScannerLLMError.invalidResponse("bad URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
        You extract payslip data from noisy OCR text (Hebrew, English or Arabic). Israeli
        payslips (תלוש שכר) are the most common input — a dense multi-column table, not a
        simple form, so read every row of the payments/deductions tables rather than only
        the summary lines.

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
          "overtime_lines":   [{"rate_percent": 125, "hours": 0.0, "amount": 0.0}],
          "deduction_lines":  [{"label": "string", "amount": 0.0}],
          "confidence":       0.0,
          "notes":            "short free text | null"
        }

        Vocabulary hints:
        - Pay: Hebrew שכר ברוטו / ברוטו / סה"כ תשלומים = gross_pay; שכר נטו / נטו / לתשלום =
          net_pay. English Gross / Gross Pay = gross_pay; Net / Net Pay / Take Home = net_pay.
          Arabic صافي = net_pay; إجمالي / الراتب الإجمالي = gross_pay.
        - Hours: Hebrew שעות עבודה / שעות רגילות (often on the row labeled משכורת or 001) =
          hours_regular. Overtime is usually split across SEVERAL rows by rate, each row's
          own "כמות"/"quantity" column being that tier's hours — e.g. ש.נוספות 125%,
          ש.נוס 150%, גמול שעות נוספות. Put each such row into `overtime_lines` (rate_percent
          parsed from the row label, e.g. "125% ש.נוספות" → 125) and set `hours_ot` to the
          SUM of every overtime row's hours (not just one row, and not 0 when overtime rows
          exist). English "Overtime" / "OT" behave the same way.
        - Deductions: Hebrew ניכויי חובה / ניכויים / נכויים — this is a distinct table from
          the payments table, usually listing rows like ביטוח לאומי, מס בריאות, מס הכנסה,
          קרן פנסיה, each with its own amount. Put each row into `deduction_lines` and set
          `deductions_total` to their sum (use the printed סה"כ ניכויי חובה total if present
          instead of summing yourself, when it's visible). English "Deductions" / "Tax"
          behave the same way. Arabic خصم / خصومات.
        - Employer vs. department: `employer_name` is the company at the TOP of the payslip,
          usually next to חברה / שם המעסיק / a company-number line. A line labeled מחלקה
          (department) is NOT the employer even when it contains a person's name (e.g. a
          department named after its manager) — never use it for employer_name.
        - Employee: עובד / שם העובד / לכבוד (the "To" block, often just above an address) =
          employee_name.

        Rules for dates — read carefully, this is the most common mistake:
        - `payment_month` is the month the payslip COVERS, normally printed as
          "תלוש שכר לחודש MM/YYYY" or "לחודש MM/YYYY". It is almost never the same as a
          separately printed "הודפס בתאריך" / "printed on" date — that is only when the
          document was generated and must be ignored for payment_month and period purposes.
        - `pay_period_start` / `pay_period_end` should only be filled from an EXPLICIT
          "מתאריך .. עד תאריך" / "period" range for THIS payslip. Do not use an unrelated
          date such as "תחילת עבודה" (the employee's overall employment start date — a
          one-time hire date, not this period) or the print date. If no explicit period
          range is printed, leave both null; the app derives the period from payment_month.
        - Sanity check: pay_period_start must not be after pay_period_end. If your extracted
          pair would violate that, the dates were misread — set both to null instead of
          guessing.

        Other rules:
        - NEVER invent monetary amounts. If a value is not clearly present, use null and
          lower the confidence.
        - Numbers may be formatted as 1,234.56 or 1.234,56 or 1234.56 — normalise to a plain
          number (dot as decimal separator, no thousands separators).
        - Dates should be DD/MM/YYYY (day first) when order is ambiguous.
        - `overtime_lines` and `deduction_lines` are `[]` (not null) when the payslip has no
          such breakdown — never omit the keys.
        - `confidence` is 0..1. Use < 0.6 when several key fields are unclear, including when
          hours_regular/hours_ot/deductions_total were left at 0 for lack of a clear source
          (0 must mean "confirmed zero on the payslip", never "couldn't find it").

        OCR:
        \(ocrText)
        """
    }
}
