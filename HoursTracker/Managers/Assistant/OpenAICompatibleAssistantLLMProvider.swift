import Foundation

/// Second choice: any OpenAI-compatible Chat Completions endpoint (OpenAI, Groq,
/// OpenRouter, …), using the same secondary Keychain key and the same host inference by
/// key prefix as the scanners, so a user configures one key and everything uses it.
struct OpenAICompatibleAssistantLLMProvider: AssistantLLMProviding {
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

    func plan(question: String, context: AssistantPlannerContext) async throws -> AssistantPlan {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScannerLLMError.missingAPIKey
        }
        let sanitized = AssistantPrompt.sanitize(question: question)
        guard !sanitized.isEmpty else {
            throw ScannerLLMError.emptyResult
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": AssistantPrompt.instructions(context: context)],
                ["role": "user", "content": sanitized]
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
                throw ScannerLLMError.network("HTTP \(http.statusCode)")
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String
        else {
            throw ScannerLLMError.invalidResponse("missing choices")
        }

        return try AssistantPlan.decode(from: text)
    }
}
