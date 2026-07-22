# Smart Scanner

On-device timesheet OCR with an optional cloud LLM structuring step.

## Privacy (default: local only)

- `smartScannerCloudEnabled` (UserDefaults) defaults to **false**.
- While off, Vision OCR text is parsed with the local heuristic only — nothing leaves the device.
- When the user opts in (Settings → Smart Scanner), OCR **text** (not images) may be sent to cloud providers to structure rows.
- API keys are stored in the Keychain (`geminiAPIKey`, `secondaryAPIKey`), never in source, plist, or git.

## Setting API keys

1. Open **Settings → Smart Scanner**.
2. Enable **Use cloud AI for structuring**.
3. Paste your **Gemini** API key (priority 1).
4. Optionally paste a **secondary** OpenAI-compatible key (priority 2 — defaults to Groq’s Chat Completions API).
5. Tap **Save** — keys are written to Keychain.

Do **not** put keys in env files committed to the repo.

## Pipeline

1. Vision OCR (or PDF/text import) → raw text.
2. Job runs on `AppViewModel` in the **background** — the pick UI dismisses so the user can keep using the app. A compact banner shows progress; when ready, a review sheet opens (no silent auto-save).
3. If cloud enabled → `ScannerLLMRouter` tries providers in order:
   1. **Gemini** (`gemini-2.5-flash` as of mid-2026; free-tier limits change — check Google AI Studio)
   2. **OpenAI-compatible** secondary (Groq by default)
   3. **Local** regex/heuristic (always available offline)
   - On HTTP 429 / quota / network / missing key → next provider without a blocking error.
4. `ScannerRowValidator` accepts rows with hours in `(0, 16]`, requires `out > in`, and marks equal in/out (≈24h overnight trap) as `needsManualReview` instead of inventing a full-day shift.
5. Review UI shows drafts; ⓘ opens processing details (winning provider, accept / review / reject counts). **Human confirm before DB write.**

## Files

| File | Role |
|------|------|
| `Managers/Scanner/ScannerLLMModels.swift` | JSON row schema + processing details |
| `Managers/Scanner/ScannerLLMProviding.swift` | Provider protocol |
| `Managers/Scanner/GeminiScannerLLMProvider.swift` | Gemini `generateContent` via URLSession |
| `Managers/Scanner/OpenAICompatibleScannerLLMProvider.swift` | Priority-2 Chat Completions fallback |
| `Managers/Scanner/LocalHeuristicScannerLLMProvider.swift` | Existing regex parser as “Local” |
| `Managers/Scanner/ScannerLLMRouter.swift` | Ordered fallback |
| `Managers/Scanner/ScannerRowValidator.swift` | Hours / equal-time guards |
| `Utilities/SmartScannerCloudPreference.swift` | Opt-in flag |
