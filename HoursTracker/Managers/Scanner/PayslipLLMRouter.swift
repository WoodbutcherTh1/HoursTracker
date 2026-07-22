import Foundation

/// Mirrors `ScannerLLMRouter` but drives the payslip providers. Order is:
///   1. Gemini (if `includeCloud` and key present)
///   2. OpenAI-compatible (Groq / OpenRouter / OpenAI etc. — key present)
///   3. Local heuristic (always in the chain)
///
/// Payslip cloud use is gated by the same `SmartScannerCloudPreference` used by the
/// timesheet scanner — there is intentionally no second toggle at this stage. The
/// caller is expected to pass `includeCloud: SmartScannerCloudPreference.isEnabled`.
struct PayslipLLMRouter: Sendable {
    private let providers: [any PayslipLLMProviding]

    init(providers: [any PayslipLLMProviding]) {
        self.providers = providers
    }

    static func `default`(
        includeCloud: Bool,
        geminiKey: String? = KeychainStore.string(for: .geminiAPIKey),
        secondaryKey: String? = KeychainStore.string(for: .secondaryAPIKey)
    ) -> PayslipLLMRouter {
        var providers: [any PayslipLLMProviding] = []
        if includeCloud {
            providers.append(GeminiPayslipLLMProvider(apiKey: geminiKey))
            providers.append(OpenAICompatiblePayslipLLMProvider(apiKey: secondaryKey))
        }
        providers.append(LocalHeuristicPayslipLLMProvider())
        return PayslipLLMRouter(providers: providers)
    }

    func extractPayslip(ocrText: String) async -> PayslipLLMStructureResult {
        var lastError: ScannerLLMError?
        var localFallback: PayslipLLMStructureResult?

        for provider in providers {
            do {
                let result = try await provider.extractPayslip(ocrText: ocrText)
                if result.hasAnyPrimaryValue {
                    return result
                }
                // Empty local result is still worth surfacing when cloud providers failed.
                if provider.name == LocalHeuristicPayslipLLMProvider().name {
                    localFallback = result
                }
                lastError = .emptyResult
            } catch let error as ScannerLLMError {
                lastError = error
                continue
            } catch {
                lastError = .network(error.localizedDescription)
                continue
            }
        }

        if let localFallback {
            return localFallback
        }
        return PayslipLLMStructureResult(
            fields: PayslipLLMFields(confidence: 0.0),
            providerName: providers.last?.name ?? "none",
            rawJSON: lastError.map { "error: \($0)" },
            needsManualReview: true
        )
    }
}
