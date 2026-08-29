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

    /// `cloudEnabled` is the same `SmartScannerCloudPreference` toggle the scanners
    /// honour. The assistant reuses the scanner's API key, so it must also respect the
    /// scanner's opt-out: a user who turns cloud extraction back off in Settings has
    /// withdrawn consent for their data to leave the device, and that has to apply to
    /// the free-text question they type here too — not just to OCR text. With the toggle
    /// off there are no providers, so the chat reports itself as not set up.
    static func `default`(
        geminiKey: String? = KeychainStore.string(for: .geminiAPIKey),
        secondaryKey: String? = KeychainStore.string(for: .secondaryAPIKey),
        cloudEnabled: Bool = UserDefaultsSmartScannerCloudPreference.shared.isEnabled
    ) -> AssistantLLMRouter {
        guard cloudEnabled else { return AssistantLLMRouter(providers: []) }
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
