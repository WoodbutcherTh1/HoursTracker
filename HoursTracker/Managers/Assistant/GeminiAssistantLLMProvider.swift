import Foundation

/// Gemini `generateContent`, asked for a routing decision and nothing else. The API key
/// is the user's own, read from the Keychain, exactly as the timesheet and payslip
/// scanners do — the app ships no key of its own.
struct GeminiAssistantLLMProvider: AssistantLLMProviding {
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

    func plan(question: String, context: AssistantPlannerContext) async throws -> AssistantPlan {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScannerLLMError.missingAPIKey
        }
        let sanitized = AssistantPrompt.sanitize(question: question)
        guard !sanitized.isEmpty else {
            throw ScannerLLMError.emptyResult
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ScannerLLMError.invalidResponse("bad URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": AssistantPrompt.instructions(context: context)]]
            ],
            "contents": [
                ["role": "user", "parts": [["text": sanitized]]]
            ],
            "generationConfig": [
                "temperature": 0,
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
            case 401, 403, 404:
                throw ScannerLLMError.quotaExceeded
            default:
                throw ScannerLLMError.network("HTTP \(http.statusCode)")
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw ScannerLLMError.invalidResponse("missing candidates")
        }

        return try AssistantPlan.decode(from: text)
    }
}
