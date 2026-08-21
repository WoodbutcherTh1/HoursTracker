import Foundation

/// Tries the configured providers in order — Gemini first, then any OpenAI-compatible
/// key — falling through on rate limits, quota, and network failures.
///
/// Unlike the scanner routers there is deliberately no local heuristic at the end of the
/// chain. Guessing which tool a free-text question in three languages means is not
/// something a keyword matcher does honestly, and pretending otherwise would produce
/// confidently wrong answers about someone's pay. With no key configured the assistant
/// reports itself as not set up and points at Settings, rather than appearing to work.
struct AssistantLLMRouter: Sendable {
    private let providers: [any AssistantLLMProviding]

    init(providers: [any AssistantLLMProviding]) {
        self.providers = providers
    }

    /// Whether any provider is actually usable. `false` means "no API key saved".
    var isConfigured: Bool { !providers.isEmpty }

    static func `default`(
        geminiKey: String? = KeychainStore.string(for: .geminiAPIKey),
        secondaryKey: String? = KeychainStore.string(for: .secondaryAPIKey)
    ) -> AssistantLLMRouter {
        var providers: [any AssistantLLMProviding] = []
        if hasKey(geminiKey) {
            providers.append(GeminiAssistantLLMProvider(apiKey: geminiKey))
        }
        if hasKey(secondaryKey) {
            providers.append(OpenAICompatibleAssistantLLMProvider(apiKey: secondaryKey))
        }
        return AssistantLLMRouter(providers: providers)
    }

    static func hasKey(_ key: String?) -> Bool {
        guard let key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The chosen plan, or a thrown `ScannerLLMError` when every provider failed.
    /// `.missingAPIKey` when there was nothing to try in the first place.
    func plan(question: String, context: AssistantPlannerContext) async throws -> AssistantPlan {
        guard !providers.isEmpty else {
            throw ScannerLLMError.missingAPIKey
        }

        var lastError: ScannerLLMError = .emptyResult
        for provider in providers {
            do {
                return try await provider.plan(question: question, context: context)
            } catch let error as ScannerLLMError {
                lastError = error
                continue
            } catch {
                lastError = .network(error.localizedDescription)
                continue
            }
        }
        throw lastError
    }
}
