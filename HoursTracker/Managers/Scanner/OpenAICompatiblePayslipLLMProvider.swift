import Foundation

/// Priority-2 cloud fallback for payslip extraction: OpenAI-compatible Chat Completions
/// (OpenAI, Groq, OpenRouter, etc.). Uses `KeychainStore.Key.secondaryAPIKey`. Endpoint and
/// model are inferred from the key's prefix via `OpenAICompatibleEndpoint` (falls back to
/// Groq if the prefix is unrecognized).
///
/// Sends OCR text only — no image / PDF bytes in the request body.
struct OpenAICompatiblePayslipLLMProvider: PayslipLLMProviding {
    let name = "OpenAI-compatible"
    private let apiKey: String?
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    init(
        apiKey: String? = KeychainStore.string(for: .secondaryAPIKey),
        model: String? = nil,
        baseURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        let inferred = OpenAICompatibleEndpoint.infer(fromAPIKey: apiKey)
        self.model = model ?? inferred.model
        self.baseURL = baseURL ?? inferred.baseURL
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

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45

        request.httpBody = try Self.makeRequestBody(model: model, ocrText: trimmed)

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
}

extension OpenAICompatiblePayslipLLMProvider {
    /// Testable request-body builder. The body is text-only: the system prompt goes into
    /// the `system` message and the OCR text goes into the `user` message — no image or
    /// PDF bytes are attached.
    static func makeRequestBody(model: String, ocrText: String) throws -> Data {
        let system = GeminiPayslipLLMProvider.buildPrompt(ocrText: "")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": String(ocrText.prefix(12_000))]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }
}

/// Exposed so tests can assert the payslip cloud request body contains OCR text only.
enum PayslipCloudRequestInspector {
    /// Returns the JSON top-level keys inside `httpBody` when it decodes as an object.
    static func topLevelKeys(in body: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return []
        }
        return Set(root.keys)
    }

    /// True if the request body contains any keys typically associated with attaching
    /// raw image / PDF bytes to a Gemini or OpenAI-compatible request.
    static func containsBinaryAttachment(in body: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: body) else { return false }
        return containsBinaryAttachment(in: root)
    }

    private static func containsBinaryAttachment(in value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            for (key, sub) in dict {
                let lower = key.lowercased()
                if lower == "inlinedata" || lower == "inline_data"
                    || lower == "filedata" || lower == "file_data"
                    || lower == "image_url" || lower == "image"
                    || lower == "input_image" || lower == "input_file" {
                    return true
                }
                if containsBinaryAttachment(in: sub) { return true }
            }
        } else if let arr = value as? [Any] {
            for sub in arr where containsBinaryAttachment(in: sub) {
                return true
            }
        }
        return false
    }
}
