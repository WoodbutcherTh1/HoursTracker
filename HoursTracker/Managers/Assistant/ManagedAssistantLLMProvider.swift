import Foundation

/// Free AI through the `ai-assist` Edge Function. The provider key lives on the server,
/// so the app ships no secret. Each install is limited on the server to a few requests a
/// day and a few a week; a limit shows up here as `ScannerLLMError.rateLimited`.
struct ManagedAssistantLLMProvider: AssistantLLMProviding {
    let name = "Managed"
    private let installID: String
    private let session: URLSession

    init(installID: String, session: URLSession = .shared) {
        self.installID = installID
        self.session = session
    }

    func plan(question: String, context: AssistantPlannerContext) async throws -> AssistantPlan {
        let sanitized = AssistantPrompt.sanitize(question: question)
        guard !sanitized.isEmpty else {
            throw ScannerLLMError.emptyResult
        }

        // The function takes one prompt, so the routing instructions go in front of the question.
        let prompt = AssistantPrompt.instructions(context: context) + "\n\nUser question:\n" + sanitized

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/ai-assist"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "deviceId": installID,
            "prompt": prompt
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ScannerLLMError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            break
        case 429:
            throw ScannerLLMError.rateLimited
        case 503:
            throw ScannerLLMError.missingAPIKey
        default:
            throw ScannerLLMError.network("HTTP \(status)")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["text"] as? String,
              !text.isEmpty
        else {
            throw ScannerLLMError.invalidResponse("missing text")
        }

        return try AssistantPlan.decode(from: text)
    }
}
