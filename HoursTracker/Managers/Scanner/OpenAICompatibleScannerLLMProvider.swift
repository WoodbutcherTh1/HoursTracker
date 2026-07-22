import Foundation

/// Priority-2 cloud fallback: OpenAI-compatible Chat Completions (OpenAI, Groq, OpenRouter, etc.).
/// Uses `KeychainStore.Key.secondaryAPIKey`. Endpoint defaults to Groq’s free-tier-friendly base URL.
struct OpenAICompatibleScannerLLMProvider: ScannerLLMProviding {
    let name = "OpenAI-compatible"
    private let apiKey: String?
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    init(
        apiKey: String? = KeychainStore.string(for: .secondaryAPIKey),
        model: String = "llama-3.3-70b-versatile",
        baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
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

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45

        let system = """
        Extract timesheet rows from OCR text. Reply with ONLY JSON:
        {"rows":[{"date":"DD/MM/YYYY","clock_in":"HH:MM","clock_out":"HH:MM","total_hours":0,"confidence":0.0}]}
        Rules: skip headers; do not invent overnight shifts when two identical times appear \
        (likely a daily total); clock times are 24h HH:MM; confidence 0..1.
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": String(trimmed.prefix(12_000))]
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
            case 401, 403:
                throw ScannerLLMError.quotaExceeded
            default:
                let snippet = String(data: data, encoding: .utf8) ?? ""
                if snippet.localizedCaseInsensitiveContains("quota")
                    || snippet.localizedCaseInsensitiveContains("rate_limit") {
                    throw ScannerLLMError.quotaExceeded
                }
                throw ScannerLLMError.network("HTTP \(http.statusCode)")
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String
        else {
            throw ScannerLLMError.invalidResponse("missing choices")
        }

        let jsonText = GeminiScannerLLMProvider.extractJSONObject(from: text)
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
}
