import Foundation

/// Calls Google Gemini `generateContent` over URLSession. API key is read from Keychain
/// (or injected for tests) — never hardcode secrets.
struct GeminiScannerLLMProvider: ScannerLLMProviding {
    let name = "Gemini"
    private let apiKey: String?
    private let model: String
    private let session: URLSession

    init(
        apiKey: String? = KeychainStore.string(for: .geminiAPIKey),
        model: String = "gemini-2.0-flash",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func structure(ocrText: String) async throws -> ScannerLLMStructureResult {
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

        let prompt = """
        Extract timesheet rows from the OCR text below.
        Return ONLY valid JSON matching this schema (no markdown):
        {"rows":[{"date":"DD/MM/YYYY","clock_in":"HH:MM","clock_out":"HH:MM","total_hours":0,"confidence":0.0}]}
        Rules:
        - date is day/month/year when ambiguous
        - clock_in and clock_out are 24h HH:MM
        - do not invent overnight shifts when two identical times appear (likely a hours total)
        - skip header rows
        - confidence 0..1

        OCR:
        \(trimmed.prefix(12_000))
        """

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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
                // Quota / billing / model access issues → fall through.
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

        let jsonText = Self.extractJSONObject(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw ScannerLLMError.invalidResponse("empty JSON")
        }

        do {
            let payload = try JSONDecoder().decode(ScannerLLMPayload.self, from: jsonData)
            return ScannerLLMStructureResult(
                rows: payload.rows,
                providerName: name,
                rawJSON: jsonText
            )
        } catch {
            throw ScannerLLMError.invalidResponse(error.localizedDescription)
        }
    }

    /// Strips optional markdown fences Gemini sometimes still emits.
    static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }
}
