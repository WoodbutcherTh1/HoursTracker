import Foundation

/// Tries cloud / local providers in order. On 429, quota, or network failure, falls through.
struct ScannerLLMRouter: Sendable {
    private let providers: [any ScannerLLMProviding]

    init(providers: [any ScannerLLMProviding]) {
        self.providers = providers
    }

    /// Default order: Gemini (if keyed) → local heuristic.
    static func `default`(
        includeCloud: Bool,
        geminiKey: String? = KeychainStore.string(for: .geminiAPIKey)
    ) -> ScannerLLMRouter {
        var providers: [any ScannerLLMProviding] = []
        if includeCloud {
            providers.append(GeminiScannerLLMProvider(apiKey: geminiKey))
        }
        providers.append(LocalHeuristicScannerLLMProvider())
        return ScannerLLMRouter(providers: providers)
    }

    func structure(ocrText: String) async -> ScannerLLMStructureResult {
        var lastError: ScannerLLMError?
        for provider in providers {
            do {
                let result = try await provider.structure(ocrText: ocrText)
                if !result.rows.isEmpty {
                    return result
                }
                lastError = .emptyResult
            } catch let error as ScannerLLMError {
                lastError = error
                if shouldFallback(error) {
                    continue
                }
                // Non-retriable for this provider — still try the next one.
                continue
            } catch {
                lastError = .network(error.localizedDescription)
                continue
            }
        }

        // Absolute fallback: empty rows so the caller can show a blank draft.
        return ScannerLLMStructureResult(
            rows: [],
            providerName: providers.last?.name ?? "none",
            rawJSON: lastError.map { "error: \($0)" }
        )
    }

    private func shouldFallback(_ error: ScannerLLMError) -> Bool {
        switch error {
        case .rateLimited, .quotaExceeded, .network, .missingAPIKey, .emptyResult:
            return true
        case .invalidResponse:
            return true
        }
    }
}
