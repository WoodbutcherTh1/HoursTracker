# HoursTracker — Project Brief for AI Agents

> Hand this document to any AI agent (coding assistant, code reviewer, etc.) as complete context about the HoursTracker iOS app. Last updated: 2026-09-20.

---

## 1. What this app DOES

HoursTracker is a **worker-first hours & pay tracking app for hourly employees in Israel**, localized in **English, Hebrew, and Arabic** (RTL-aware).

Core features:

- **Clock in / clock out** tracking of work sessions (current shift runs as a Live Activity on the Lock Screen).
- **Manual entry** and editing of past sessions, with history browsing, month/year picker, and shift detail sheets.
- **Timesheet scanner**: photograph or import a printed/photo timesheet (or PDF) and the app extracts clock-in/out rows on-device using Apple **Vision** (OCR) + **PDFKit**, with an optional LLM assist; low-confidence rows are flagged for manual review before import. Conflict detection on import.
- **Israeli payroll intelligence**: gross/net pay estimation with the **Israeli tax estimator** (income tax brackets), **tax credit points (נקודות זיכוי)** by marital status, **overtime calculation** (Israeli 125%/150% rules), and **Israeli holidays** awareness.
- **Payslip library**: import payslip files, review extracted records, and compare estimated vs. actual pay; history pay breakdown sheets.
- **Exports**: full data export (JSON document) and pay/history exports in a user-chosen language.
- **Home-screen widgets** with interactive clock-in/out buttons (App Intents in the widget extension), Live Activities, and deep links via the `hourstracker://` URL scheme; also home-screen quick actions.
- **Apple Watch companion app** showing the current shift state, synced from the phone.
- **Workplace location reminders**: one optional geofence (CLCircularRegion monitoring) that reminds the user on arrival at work. No continuous background location.
- **Account & cloud backup**: email sign-up with 8-digit OTP email verification (Supabase Auth), profile display (name, email, member-since, local profile photo with initials placeholder), change password, and one-tap backup/restore of all sessions + settings.
- **App Lock** via Face ID.
- **AI assistant chat** (optional): free-text questions about the user's own hours/pay, powered by a user-supplied Gemini or OpenAI-compatible API key, routed Gemini-first with fallback; tool-calling over local data.
- **Contact support / feedback** from inside the app, delivered as messages (optionally with the activity log attached) to the developer's **Telegram** channel.

## 2. What this app does NOT do

- **No employer/shift-scheduling features** — it is a personal tracker, not a workforce management tool.
- **No continuous background location tracking** — only a single-region geofence for arrival reminders (App Store Guideline 2.5.4 constraint; do not add `UIBackgroundModes: location`).
- **No payment processing** and no connection to payroll providers — it estimates; it does not pay.
- **No offline AI by default** — the assistant and LLM scanner-assist are disabled unless the user enters their own API key (stored in Keychain).
- **No multi-user/shared accounts** — one device user; sync is strictly per-user and per-device-merge (no real-time collaborative sync).
- **No ads, no analytics SDKs, no third-party tracking** — privacy-first by design.
- **No automatic photo/video cloud sync** — the profile photo is stored locally only (cloud avatar is a planned follow-up).
- **No widget programmatic installation** — Apple provides no API; the app offers a step-by-step install guide instead.

## 3. Architecture

**Pattern**: SwiftUI + MVVM with singleton manager objects.

```
HoursTracker/                    ← main iOS app target sources
  HoursTrackerApp.swift          ← @main, App lifecycle, deep-link routing
  ViewModels/                    ← AppViewModel (central observable state owner)
  Views/                         ← SwiftUI screens (Home, History, Settings,
                                    AccountSheet, Onboarding, Assistant/, Scanner-adjacent…)
  Models/                        ← value types: WorkSession, WorkplaceSettings,
                                    PayslipRecord, OvertimeCalculator,
                                    IsraeliTaxEstimator, TaxCreditPointsCalculator,
                                    IsraeliHolidays, MaritalStatus, ExportLanguage…
  Managers/                      ← singletons, one concern each (below)
  Utilities/                     ← L10n helper, SupabaseConfig, TelegramFeedbackConfig,
                                    KeychainStore, theme/style helpers
  Config/                        ← LocalSecrets.swift (local-only secrets),
                                    Secrets.xcconfig (build-setting secrets)
  Resources/                     ← Localizable.xcstrings (en/he/ar), assets
HoursTrackerWidget/              ← widget extension target (WidgetKit + App Intents)
HoursTrackerWatch/               ← watchOS companion app target
HoursTrackerTests/               ← unit tests
HoursTrackerUITests/             ← XCUITests
project.yml                      ← XcodeGen manifest (the .xcodeproj is generated)
```

**Key shared-code pattern**: wire-format types are compiled into *both* sides of a channel — `WidgetBridge.swift` into app + widget extension (App Group + ActivityKit attributes), `Shared/WatchSnapshot.swift` into app + Watch app (WatchConnectivity payload).

**Key managers** (all in `Managers/`):

| Manager | Responsibility |
|---|---|
| `PersistenceManager` | Local JSON file store (sessions + settings) in Documents. Careful failure semantics: transient read failures return `.temporarilyUnavailable` and must **never** collapse to "empty store" (protects against silent data wipe); corrupt files are quarantined to a `.corrupt` sibling. |
| `SyncingPersistenceStore` | Wraps local persistence; mirrors every mutation to the signed-in user's cloud backup. |
| `CloudKitSyncManager` | Optional CloudKit private-DB sync (sessions + settings, merge with tombstones). Entitlement-gated; `NoOpCloudSyncManager` substitutes when iCloud isn't entitled/available. Protocol `CloudSyncing` abstracts it for tests. |
| `SupabaseAuthManager` | Supabase email/password auth, 8-digit OTP verification, session state, change password (`auth.update`). |
| `SupabaseAccountSyncManager` | Upload/download of the account backup (settings + all sessions as one JSONB row) + `profiles` name fields. ISO-8601 date strategy explicitly pinned to match local persistence. |
| `AccountProfileStore` | Local profile photo (downscaled JPEG in Documents) + display-name fallback logic. |
| `TimesheetScannerManager` (+ `Managers/Scanner/`) | Vision OCR / PDFKit pipeline, LLM-assist router, confidence scoring. |
| `Managers/Assistant/` | `AssistantEngine` (tool-calling over local data), `AssistantLLMRouter` (Gemini → OpenAI-compatible fallback, no keyword-guessing fallback), providers in `OpenAICompatibleAssistantLLMProvider` / `GeminiAssistantLLMProvider`. |
| `TelegramFeedbackSender` | Multipart/form-data POSTs to the Telegram Bot API (sendMessage + sendDocument). |
| `WidgetIntegration`, `LiveActivityManager` | Widget timeline/state bridging via App Group; Live Activity lifecycle. |
| `WatchConnectivityManager` | Phone ↔ Watch snapshot sync. |
| `LocationReminderManager` | Single CLCircularRegion geofence arrival reminder. |
| `ExportManager`, `FullDataExportManager` | User-facing exports. |
| `PayslipStore`, `ActivityLogStore`, `SessionTombstoneStore` | Payslip records, diagnostic activity log, deleted-session tombstones for merge. |

**State flow**: `Views` → `AppViewModel` (`@MainActor`, owns stores/managers) → `PersistenceManager` (source of truth is local disk; cloud is a mirror/backup, merge-on-sync, never the live store).

**Build system**: **XcodeGen** — edit `project.yml`, run `xcodegen generate`; do not hand-edit the `.xcodeproj`. Swift 5.9, iOS deployment target **17.0**, watchOS **10.0**; builds must use **Xcode 26.x** (App Store requirement as of April 2026). App version currently 1.6 (build 21); version trains 1.2/1.3/1.5 are permanently closed on App Store Connect — new submissions need a higher marketing version.

## 4. Tech stack — what is used

- **Language/UI**: Swift 5.9, SwiftUI (no UIKit screens; UIKit only where APIs demand it), String Catalogs for localization (en/he/ar), `os.Logger` for diagnostics (subsystem `com.hourstracker.app`).
- **Apple frameworks**: WidgetKit, ActivityKit (Live Activities), CloudKit, Vision + PDFKit (OCR), CoreLocation (geofencing only), WatchConnectivity, PhotosUI/PhotosPicker, LocalAuthentication (Face ID), App Intents (widget buttons), UserNotifications, os.
- **Third-party**: exactly **one** — `supabase-swift` via SPM (`from: 2.0.0`, currently resolving 2.55.2). Everything else is first-party.
- **Tooling**: XcodeGen, `xcodebuild` CLI builds, Swift Concurrency (async/await, `@MainActor`, Swift 6 strict-concurrency aware).

## 5. Backend, database, auth

- **Backend: Supabase** (hosted). Project URL + publishable anon key live in `HoursTracker/Utilities/SupabaseConfig.swift` and **are meant to ship in the client** — security is enforced **server-side by Postgres Row Level Security (RLS)**, not by hiding the key.
- **Database: PostgreSQL** (Supabase). Tables used by the app:
  - `user_backups` — one row per user: `user_id`, `payload` (**JSONB** containing `{settings, sessions[]}` — the whole restore set), `app_version`. Upserted on every sync.
  - `profiles` — `id` (= auth user id), `full_name`, `family_name`. Display name for the account screen.
  - Supabase Auth's own tables back email accounts.
- **Auth: Supabase Auth (GoTrue)** — email + password sign-up, **8-digit email OTP** confirmation (the project's dashboard OTP-length setting is 8; the app enforces exactly 8 digits — keep them in sync). Error handling uses the SDK's structured `AuthError` `errorCode` (e.g. `.otpExpired`), **never** substring matching on `localizedDescription`.
- **Secondary cloud**: Apple **CloudKit private database** (container `iCloud.com.hourstracker.app`), entitlement-gated and off in personal-team builds; merge-based sync with tombstones.

## 6. Connections (network & integrations)

| Channel | Transport | Purpose |
|---|---|---|
| Supabase (REST/PostgREST via supabase-swift) | HTTPS | Auth, `user_backups` upsert/select, `profiles` upsert/select |
| Supabase Auth | HTTPS | Sign-up/sign-in, OTP verify, password change, session refresh |
| Telegram Bot API | HTTPS (JSON `sendMessage`, multipart/form-data `sendDocument`) | In-app Contact Support feedback → developer's Telegram channel |
| Gemini API / any OpenAI-compatible endpoint | HTTPS REST | Assistant chat + optional scanner LLM assist; keys user-supplied, stored in **Keychain** (`KeychainStore`); router falls back Gemini-first |
| CloudKit | Apple framework | Optional iCloud private-DB backup/sync |
| WatchConnectivity | Bluetooth/on-body | Phone ↔ Watch shift snapshots |
| App Group (`group.com.hourstracker.app` pattern — see entitlements) | Local IPC | App ↔ widget shared state; widget buttons deep-link back via `hourstracker://` |

**Secrets policy (important)**:
- `LocalSecrets.swift` holds the Telegram bot token + chat ID **locally only** — it is committed with empty placeholders and the real values are kept out of git via `git update-index --skip-worktree`. Never commit real values there; the repo is **public** and one token was historically leaked and had to be rotated.
- `Secrets.xcconfig` carries build-setting-level secrets via `$(VAR)` substitution into Info.plist; committed with empty values.
- LLM API keys never touch disk files — **Keychain only**.

## 7. How it works (end-to-end data flow)

1. **Launch**: `HoursTrackerApp` → `AppViewModel` loads sessions + settings from `PersistenceManager` (JSON in Documents). Load failures are triaged (`missing` / `temporarilyUnavailable` / `corruptQuarantined`) so a transient read error can never wipe data.
2. **Clock in/out**: UI (or widget button via App Intent + deep link, or Watch) mutates `AppViewModel` state → `PersistenceManager` writes JSON → side effects fire: Live Activity start/update, widget timeline reload (via App Group), Watch snapshot push, geofence arming, optional mirrored cloud write through `SyncingPersistenceStore`.
3. **Sync (account backup)**: signed-in user taps Sync (or mutation occurs with `SyncingPersistenceStore` active) → `SupabaseAccountSyncManager.uploadBackup` encodes `{settings, sessions}` as ISO-8601 JSON → upserts into `user_backups` (RLS scopes it to `auth.uid()`), and refreshes `profiles`. Download reverses this and merges into the local store. CloudKit path (if enabled) does field-level merge with tombstones instead.
4. **Scanner**: photo/PDF → Vision OCR (or PDFKit text) → candidate shift rows → optional LLM cleanup via `AssistantLLMRouter`-style provider chain → user reviews confidence-flagged drafts → conflict check against existing sessions → import.
5. **Pay math**: `WorkSession` list + `WorkplaceSettings` → `OvertimeCalculator` / `IsraeliTaxEstimator` / `TaxCreditPointsCalculator` (+ `IsraeliHolidays`) → live pay cards, history breakdowns, and export documents. Estimation only — clearly labeled.
6. **Assistant**: user question + local data summary → `AssistantEngine` plans tool calls (reads sessions/settings locally) → `AssistantLLMRouter` asks Gemini (falls back to OpenAI-compatible) → grounded answer. With no key configured it reports itself as not set up rather than pretending.
7. **Feedback**: `ContactSupportSheet` → `TelegramFeedbackSender` (optionally attaching `ActivityLogStore` export) → Bot API → developer's Telegram channel.
8. **Widgets/Live Activities**: extension reads shared state from the App Group, renders timelines, interactive buttons run App Intents that mutate the app's store and `WidgetCenter`-reload; deep links (`hourstracker://`) route back into specific screens.

## Quick facts

- **Bundle IDs**: `com.hourstracker.app` (+ `.widget`, `.watchkitapp`, `.tests`, `.uitests`). Team `FQUC6DU87N`.
- **Targets**: app, widget extension, watchOS app, unit tests, UI tests.
- **Minimums**: iOS 17.0 / watchOS 10.0. Build with Xcode 26.x.
- **Testing**: `xcodebuild -project HoursTracker.xcodeproj -scheme <scheme>` for app and test targets; unit tests cover persistence, calculators, sync merge logic.
- **Local debugging**: run `xcodegen generate` after editing `project.yml`; fill `LocalSecrets.swift` locally (skip-worktree) for feedback; widget data needs the App Group entitlements intact.
- **Known sharp edges**: (1) never let a transient store-read failure become an empty-store overwrite; (2) Supabase OTP length (dashboard) must match the app's 8-digit entry; (3) don't add background-location modes (App Store rejection history); (4) version trains below 1.6 are closed on App Store Connect; (5) never commit real Telegram tokens — rotate immediately if leaked.
