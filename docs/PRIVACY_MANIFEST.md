# Privacy manifest reasoning

`HoursTracker/Resources/PrivacyInfo.xcprivacy` must stay aligned with real behavior and with App Store Connect’s App Privacy questionnaire.

## Why most data is “Not Collected”

Apple’s “collected” types mean data that is transmitted off the device to the developer or to a third party, for purposes such as analytics, advertising, or a server the developer operates.

HoursTracker:

- Stores data in the app sandbox (JSON + Keychain) and optional **user-private** CloudKit database
- Has **no** developer backend, analytics, crash reporter, or advertising SDK
- Never sends national ID to iCloud (Keychain, ThisDeviceOnly)

Optional iCloud sync is the user’s Apple ID private database — it is not developer “collection” in the App Privacy sense.

## Exception: Smart Scanner cloud extraction (opt-in)

When the user turns on **Smart Scanner cloud extraction** in Settings (`SmartScannerCloudPreference`, default **off**), OCR text from a photographed timesheet or payslip is sent to a third-party LLM API — **Google Gemini** or an OpenAI-compatible endpoint (e.g. Groq) — to structure the data (`GeminiPayslipLLMProvider`, `OpenAICompatiblePayslipLLMProvider`, and the timesheet equivalents). This can include employer name, employee name, and pay figures extracted from the document.

- **Off by default**; nothing is sent until the user enables it and supplies their own API key (stored in Keychain, `ThisDeviceOnly`).
- **Text only** — the request body carries the OCR string, never the original image/PDF bytes (enforced and tested via `PayslipCloudRequestInspector.containsBinaryAttachment`).
- Sent directly from the device to Google’s / the OpenAI-compatible provider’s endpoint over HTTPS; HoursTracker does not proxy or log this traffic.
- Declared in `NSPrivacyCollectedDataTypes` as `NSPrivacyCollectedDataTypeOtherFinancialInfo`, not linked to identity, not used for tracking, purpose `AppFunctionality`.

This is a real exception to the "no networking layer" description in `docs/ARCHITECTURE.md`'s networking gate — see that doc's "Networking gate" section for the current state. If more networking is added, update this file, `docs/DATA_INVENTORY.md`, `docs/PRIVACY.md`, and the App Store Connect questionnaire before shipping. **Verify the exact `NSPrivacyCollectedDataType*` category/purpose constants against current Apple documentation before submission — categories can change between OS releases.**

## Required-reason APIs

| API category | Reason | Why |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `iCloudSyncEnabled` opt-in flag (`CloudSyncPreference`) |

No file-timestamp, disk-space, boot-time, or active-keyboard required-reason APIs are used for tracking. `FileManager.attributesOfItem` is used only for Data Protection class / file size checks in security paths — if App Review ever flags file timestamps, add the matching reason only after confirming the exact API.

## Keep in sync

When changing storage, logging, export, or networking, update:

1. `PrivacyInfo.xcprivacy`
2. `docs/PRIVACY.md` and in-app `PrivacyPolicyView` strings
3. `docs/DATA_INVENTORY.md` (Phase 6)
4. App Store Connect App Privacy answers
