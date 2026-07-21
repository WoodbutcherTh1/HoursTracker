# Smart Scanner

On-device timesheet OCR with an optional cloud LLM structuring step.

## Privacy (default: local only)

- `smartScannerCloudEnabled` (UserDefaults) defaults to **false**.
- While off, Vision OCR text is parsed with the local heuristic only — nothing leaves the device.
- When the user opts in (Settings → Smart Scanner), OCR **text** (not images) may be sent to Google Gemini to structure rows.
- API keys are stored in the Keychain (`KeychainStore.Key.geminiAPIKey`), never in source, plist, or git.

## Setting the Gemini API key

1. Open **Settings → Smart Scanner**.
2. Enable **Use cloud AI for structuring**.
3. Paste your Gemini API key into the secure field.
4. Tap **Save** — the key is written to Keychain (`geminiAPIKey`).

Alternatively (debug / scripts), write the key with Keychain APIs for account `geminiAPIKey` under service `com.hourstracker.app`. Do **not** put keys in env files committed to the repo.

Optional secondary key slot: `KeychainStore.Key.secondaryAPIKey` (reserved for a future provider).

## Pipeline

1. Vision OCR (or PDF/text import) → raw text.
2. If cloud enabled → `ScannerLLMRouter` tries providers in order (Gemini → Local).
   - On HTTP 429 / quota / network / missing key → next provider.
3. `ScannerRowValidator` accepts rows with hours in `(0, 16]`, requires `out > in`, and marks equal in/out (≈24h overnight trap) as `needsManualReview` instead of inventing a full-day shift.
4. Review UI shows drafts; ⓘ opens processing details (winning provider, accept / review / reject counts).

## Files

| File | Role |
|------|------|
| `Managers/Scanner/ScannerLLMModels.swift` | JSON row schema + processing details |
| `Managers/Scanner/ScannerLLMProviding.swift` | Provider protocol |
| `Managers/Scanner/GeminiScannerLLMProvider.swift` | Gemini `generateContent` via URLSession |
| `Managers/Scanner/LocalHeuristicScannerLLMProvider.swift` | Existing regex parser as “Local” |
| `Managers/Scanner/ScannerLLMRouter.swift` | Ordered fallback |
| `Managers/Scanner/ScannerRowValidator.swift` | Hours / equal-time guards |
| `Utilities/SmartScannerCloudPreference.swift` | Opt-in flag |
