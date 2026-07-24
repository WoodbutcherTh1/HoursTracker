import Foundation

/// Infers which OpenAI-compatible host a user's secondary API key belongs to, so the
/// single "Secondary API key" field in Settings can route requests correctly without
/// asking the user to also pick a provider or type a base URL.
///
/// Previously both `OpenAICompatibleScannerLLMProvider` and
/// `OpenAICompatiblePayslipLLMProvider` hardcoded Groq's endpoint. A valid key from any
/// other OpenAI-compatible service (OpenRouter, plain OpenAI, etc.) would authenticate
/// against the wrong host, fail with 401/403, and the router would silently fall back to
/// the much weaker on-device heuristic — looking like "the AI isn't filling anything in"
/// with no indication why.
enum OpenAICompatibleEndpoint {
    /// Recognized by key prefix. Unknown prefixes fall back to Groq — this app's
    /// original default — so existing Groq users are unaffected.
    static func infer(fromAPIKey apiKey: String?) -> (baseURL: URL, model: String) {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if key.hasPrefix("sk-or-") {
            // OpenRouter: https://openrouter.ai/docs — keys are prefixed "sk-or-v1-...".
            return (URL(string: "https://openrouter.ai/api/v1")!, "openai/gpt-4o-mini")
        }
        if key.hasPrefix("gsk_") {
            // Groq: keys are prefixed "gsk_...".
            return (URL(string: "https://api.groq.com/openai/v1")!, "llama-3.3-70b-versatile")
        }
        if key.hasPrefix("sk-") {
            // Plain OpenAI: keys are prefixed "sk-..." (or "sk-proj-...").
            return (URL(string: "https://api.openai.com/v1")!, "gpt-4o-mini")
        }
        return (URL(string: "https://api.groq.com/openai/v1")!, "llama-3.3-70b-versatile")
    }
}
