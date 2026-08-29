# HoursTracker — Data Inventory

Definition-of-done for privacy changes: if a PR stores, logs, exports, or transmits new user data, update this file, `PrivacyInfo.xcprivacy`, and `docs/PRIVACY.md`.

**Protection class (files):** `.completeFileProtectionUnlessOpen` via `ProtectedFileWriter` unless noted.  
**Delete path:** `AppViewModel.deleteAllUserData()` unless noted.

## Identity & workplace settings (`workplace_settings.json` + Keychain)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| `workerIDNumber` (national ID) | **Keychain** only (empty in JSON/CloudKit) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Until delete / empty save | Keychain delete via settings reset |
| `geminiAPIKey`, `secondaryAPIKey` (Smart Scanner cloud + Assistant) | **Keychain** only, user-supplied | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Until delete / empty save | Keychain delete via Settings |
| `workerFullName` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `employeeNumber` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `workplaceName`, `contractorName` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `locationLatitude` / `locationLongitude` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `locationRadiusMeters` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| Pay rates, OT caps, breaks, currency | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| Marital status, children, spouse employed | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `payrollStartDay`, `restDayWeekday`, `arrivalRemindersEnabled` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `modifiedAt` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |

## Work history (`work_sessions.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Session id, dates, clock in/out, break, day type, night flag, notes, `modifiedAt`, import flags | Documents JSON; one CloudKit record per session if sync on | File protection | Until delete | Local + cloud purge |
| Corrupt decode sidecar | `work_sessions.json.corrupt*` | Same directory | Until delete-all or manual | `wipeQuarantinedSidecars` |

## Activity log (`activity_log.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Event message, level, category, timestamp, optional **non-PII** details | Documents JSON (not CloudKit) | File protection | Cap ~500 entries; until wipe | `wipeForPrivacy` / delete-all |

**Rule:** details may contain event names, counts, durations, and format identifiers only — **never** PII, GPS coordinates, or free-text notes.

## Sync control & App Lock (UserDefaults)

| Key | Purpose | Protection | Retention | Deleted by |
|---|---|---|---|---|
| `iCloudSyncEnabled` | User opt-in for CloudKit (default off) | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |
| `appLockEnabled` | Optional biometric App Lock (default off) | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |
| `smartScannerCloudEnabled` | User opt-in for cloud LLM document extraction **and** the cloud Assistant (default off) | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |
| `assistantButtonEnabled`, `assistantButtonStyle` | Assistant nav-bar button visibility + icon choice | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |

Privacy manifest reason: `CA92.1` (see `PrivacyInfo.xcprivacy`).

## Payslip library (`payslips/` — `PayslipStore`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Uploaded payslip file (image/PDF) | `payslips/files/` under app container | File protection | Until delete | `AppViewModel.deleteAllUserData()` (verify payslip wipe is wired in) |
| Extracted fields (gross/net pay, employer/employee name, dates, hours) | `payslips/index.json` | File protection | Until delete | Same |
| `PayslipExtraction.rawJSON`, `providerName` | Same index file | File protection | Until delete | Same |

**Note:** if the app-groups entitlement is absent (personal-team builds), `PayslipStore` falls back to the app's own Documents directory rather than a shared container — confirm this is the intended behavior before relying on any future widget/extension sharing this data.

## Third-party transmission — cloud AI features (opt-in, default off)

| What | Sent to | Trigger | Contains |
|---|---|---|---|
| OCR'd timesheet/payslip text (never image/PDF bytes) | Google Gemini API, or an OpenAI-compatible endpoint (e.g. Groq) chosen by the user | Only when `smartScannerCloudEnabled` is on **and** the user supplied an API key | Employer name, employee name, pay figures, dates, hours as recognized from the document |
| Assistant question text (≤500 chars) + today's date/weekday | Same provider / key as above | Only when `smartScannerCloudEnabled` is on **and** a key is saved **and** the user sends a question (`AssistantLLMRouter`) | Whatever the user types. Never their sessions, pay, name, employer, or payslips — the model only returns the name of a report to run; all figures are computed on-device |

These are the only outbound network traffic in the app besides CloudKit. Conversation history is in-memory only (not persisted, not synced, cleared on sheet close). See `docs/PRIVACY_MANIFEST.md` and `docs/ARCHITECTURE.md` ("Networking gate") for the reasoning and the exception to the no-general-networking rule.

## Tombstones (`session_tombstones.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Deleted session UUID + `deletedAt` | Documents JSON | File protection | Pruned after 90 days; until delete-all | `removeAll` + sidecar wipe |

## Export temps (`tmp/Exports/`)

| Content | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| PDF/TXT/DOCX/MD/CSV reports (may include name, ID, pay) | App tmp `Exports/` | File protection on write | Ephemeral | Share completion, launch, background, delete-all |

## Local notifications

| Content | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Reminder titles/bodies (no national ID) | Notification center | OS-managed | Until fired / cancelled | `removeAllPending` / `removeAllDelivered` on delete-all |

## CloudKit private database (opt-in only)

| Record | Payload | National ID | Deleted by |
|---|---|---|---|---|
| `WorkSession` | JSON session blob + `modifiedAt` | Never | `purgeUserCloudData` / per-session delete |
| `workplace-settings` | Settings JSON with empty `workerIDNumber` | Never | Purge when sync off / delete-all |

## Not collected

No analytics, advertising IDs, crash reporters, or developer-operated servers. (The opt-in cloud AI features — Smart Scanner extraction and the Assistant — send text to a third-party AI provider the user configures, see the section above, but HoursTracker itself has no backend.) See `PrivacyInfo.xcprivacy` and `docs/PRIVACY_MANIFEST.md`.
