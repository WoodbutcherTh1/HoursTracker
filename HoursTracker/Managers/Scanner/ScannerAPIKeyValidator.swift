import Foundation

/// Result of a lightweight "is this key valid?" check.
enum APIKeyCheckResult: Equatable {
    case valid
    case invalid
    case networkError

    var isValid: Bool { self == .valid }
}

/// Validates Smart Scanner API keys against the provider's models-listing endpoint —
/// cheap, free on every provider we support, and doesn't consume generation quota/credits
/// the way a real extraction call would. Lets Settings show a pass/fail result immediately
/// instead of the user only finding out a key doesn't work after uploading a document and
/// watching the review screen come back empty.
enum ScannerAPIKeyValidator {
    /// GET https://generativelanguage.googleapis.com/v1beta/models
    /// Key travels in the `x-goog-api-key` header (never the URL query) so it
    /// can't leak into proxy/log lines — same rule as the extraction calls.
    static func checkGeminiKey(_ apiKey: String, session: URLSession = .shared) async -> APIKeyCheckResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            return .invalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(trimmed, forHTTPHeaderField: "x-goog-api-key")

        do {
            let (_, response) = try await session.data(for: request)
            return Self.classify(response)
        } catch {
            return .networkError
        }
    }

    /// GET {inferred base URL}/models with Bearer auth — same host inference used for the
    /// real extraction call, so this also confirms the key routes to the right provider
    /// (Groq / OpenRouter / OpenAI).
    static func checkOpenAICompatibleKey(_ apiKey: String, session: URLSession = .shared) async -> APIKeyCheckResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        let endpoint = OpenAICompatibleEndpoint.infer(fromAPIKey: trimmed)
        let url = endpoint.baseURL.appendingPathComponent("models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await session.data(for: request)
            return Self.classify(response)
        } catch {
            return .networkError
        }
    }

    private static func classify(_ response: URLResponse) -> APIKeyCheckResult {
        guard let http = response as? HTTPURLResponse else { return .networkError }
        switch http.statusCode {
        case 200..<300:
            return .valid
        case 401, 403, 400:
            return .invalid
        default:
            return .networkError
        }
    }
}
