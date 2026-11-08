# HoursTracker — Project Brief for AI Agents

> Hand this document to any AI agent (coding assistant, code reviewer, etc.) as complete context about the HoursTracker iOS app. Last updated: 2026-11-08.

---

## 1. What this app DOES

HoursTracker is a **worker-first hours & pay tracking app for hourly employees in Israel**, localized in **5 languages: English, Hebrew, Arabic, Russian, and Thai** (Hebrew and Arabic are RTL).

Core features:

- **Clock in / clock out** tracking of work sessions. The current shift runs as a **Live Activity** on the Lock Screen and in the **Dynamic Island**, and mirrors to the Home Screen widget and Apple Watch — all three read the same live pay curve, so they can never show different numbers for the same shift (see §8, Live Activity / Widget sync).
- **Manual entry** and editing of past sessions, with history browsing, month/year picker, and shift detail sheets.
- **Timesheet scanner**: photograph or import a printed/photo timesheet (or PDF) and the app extracts clock-in/out rows on-device using Apple **Vision** (OCR) + **PDFKit**, with an optional LLM assist; low-confidence rows are flagged for manual review before import. Conflict detection on import.
- **Israeli payroll intelligence**: gross/net pay estimation with the **Israeli tax estimator** (income tax brackets), **tax credit points (נקודות זיכוי)** by marital status, **overtime calculation** (Israeli 125%/150% rules), and **Israeli holidays** awareness.
- **Payslip library**: import payslip files, review extracted records, and compare estimated vs. actual pay; history pay breakdown sheets.
- **Exports**: full data export (JSON document) and pay/history exports in a user-chosen language. The Export tab has quick-pill shortcuts (This/Last Month, This/Last Week), a live mini-receipt preview (day count, hours, net pay) that recomputes off the main thread as filters change, and a "What's included" checklist naming exactly what the report calculates.
- **Home-screen widgets** with interactive clock-in/out buttons (App Intents in the widget extension), Live Activities, and deep links via the `hourstracker://` URL scheme; also home-screen quick actions.
- **Apple Watch companion app** showing the current shift state, synced from the phone.
- **Workplace location reminders**: one optional geofence (CLCircularRegion monitoring) that reminds the user on arrival at work. No continuous background location.
- **Account & cloud backup**: email sign-up with 8-digit OTP email verification (Supabase Auth), profile display (name, email, member-since, local profile photo with initials placeholder), change password, and one-tap backup/restore of all sessions + settings.
- **App Lock** via Face ID.
- **Two AI surfaces**, both free-text chat over the user's own data, with different backing:
  - **BYOK assistant**: the user supplies their own Gemini or OpenAI-compatible API key (stored in Keychain); routed Gemini-first with fallback.
  - **Managed assistant** (`ai-assist` Edge Function): a developer-funded free tier with no key required, quota-limited per install (3/day, 10/week by default) and protected by a global daily cap and a per-IP rate limit (see §9, Backend security).
- **Contact support / feedback** from inside the app: a free-text message (optionally with the activity log attached) proxied through the `submit-feedback` Edge Function to the developer's Telegram channel, and a persistent **in-app support chat** (`support-chat`/`support-admin` Edge Functions) keyed by a per-install id, independent of having an account.
- **Owner/admin tools** (hidden, server-verified): a push-announcement composer, live install/usage dashboards, and a support inbox — all gated by checking the caller's session against `public.admins` on the server, never by hiding a screen client-side.
- **In-app User Guide**: a 9-slide onboarding walkthrough (`UserGuideSheet.swift`) that reuses the real components it teaches wherever practical (the real clock-in door button, the real theme swatches, the real Day Type picker, …) rather than static illustrations, so it can't drift from what the app actually does.

## 2. What this app does NOT do

- **No employer/shift-scheduling features** — it is a personal tracker, not a workforce management tool.
- **No continuous background location tracking** — only a single-region geofence for arrival reminders (App Store Guideline 2.5.4 constraint; do not add `UIBackgroundModes: location`).
- **No payment processing** and no connection to payroll providers — it estimates; it does not pay.
- **No offline AI by default** — the BYOK assistant and LLM scanner-assist are disabled unless the user enters their own API key; the managed assistant requires server connectivity and is itself rate-limited.
- **No multi-user/shared accounts** — one device user; sync is strictly per-user and per-device-merge (no real-time collaborative sync).
- **No ads, no analytics SDKs, no third-party tracking** — privacy-first by design.
- **No automatic photo/video cloud sync** — the profile photo is stored locally only (cloud avatar is a planned follow-up).
- **No widget programmatic installation** — Apple provides no API; the app offers a step-by-step install guide instead.

## 3. Architecture

**Pattern**: SwiftUI + MVVM with singleton manager objects. The app is **dark-only**: every surface paints its own dark surface (`.preferredColorScheme(.dark)` pinned at the root) regardless of the system appearance, so the user-customizable background (`AppBackgroundTheme`) always shows through consistently.

```
HoursTracker/                    ← main iOS app target sources
  HoursTrackerApp.swift          ← @main, App lifecycle, deep-link routing, the 5-tab TabView
  AppDelegate.swift              ← UIKit lifecycle hooks, quick actions, UITEST_* launch-arg hooks (DEBUG only)
  ViewModels/                    ← AppViewModel (central observable state owner)
  Views/                         ← SwiftUI screens — Home, History, Payslips, Export, Settings,
                                    AccountSheet, Onboarding, UserGuideSheet, admin screens,
                                    Scanner-adjacent review views…
  Models/                        ← value types: WorkSession, WorkplaceSettings,
                                    PayslipRecord, OvertimeCalculator,
                                    IsraeliTaxEstimator, TaxCreditPointsCalculator,
                                    IsraeliHolidays, MaritalStatus, ExportLanguage…
  Managers/                      ← singletons, one concern each (below)
    Assistant/                   ← AssistantEngine, AssistantLLMRouter + BYOK/managed providers
    Scanner/                     ← Vision/PDFKit OCR pipeline, LLM-assist providers
  Intents/                       ← App Intents (Siri / Shortcuts surface)
  Shared/                        ← compiled into multiple targets at once (see "shared-code pattern" below)
  Utilities/                     ← L10n helper, SupabaseConfig, TelegramFeedbackConfig,
                                    KeychainStore, HomeAccentTheme, AppBackgroundTheme,
                                    AppLocale, DesignSystem, theme/style helpers
  Config/                        ← LocalSecrets.swift (local-only secrets),
                                    Secrets.xcconfig (build-setting secrets)
  Resources/                     ← Localizable.xcstrings (en/he/ar/ru/th, single source of truth), assets
HoursTrackerWidget/              ← widget extension target (WidgetKit + App Intents + ActivityKit)
HoursTrackerWatch/               ← watchOS companion app target
  Resources/Localizable.xcstrings  ← a SYMLINK to HoursTracker/Resources/Localizable.xcstrings —
                                      see the warning in §3 below before ever touching this
HoursTrackerTests/               ← unit tests
HoursTrackerUITests/             ← XCUITests (including UI-driven QA/screenshot automation)
supabase/                        ← Edge Functions + Postgres migrations (see §5/§9)
project.yml                      ← XcodeGen manifest (the .xcodeproj is generated)
```

**⚠️ `HoursTrackerWatch/Resources/Localizable.xcstrings` must stay a symlink.** It originally pointed at `../../HoursTracker/Resources/Localizable.xcstrings` so the Watch target has a same-directory resource to compile (Xcode's String Catalog compiler silently produces an *empty* compiled catalog for a target that references a string catalog outside its own directory tree — confirmed on-device, see commit `8eddd8c5`). Xcode's String Catalog **editor** is known to materialize that symlink into an independent real file on save. If that ever happens again, every string added to the main catalog afterward silently stops reaching the Watch app (confirmed during the 2026-11-08 cleanup pass: the materialized copy had drifted to be missing Thai entirely — 1195 of 1213 keys — while every other language stayed in sync, because the divergence started right when Thai was added to the main catalog). **Fix**: delete the regular file and recreate the symlink (`ln -s ../../HoursTracker/Resources/Localizable.xcstrings HoursTrackerWatch/Resources/Localizable.xcstrings`) — never hand-copy strings into a materialized duplicate.

**Key shared-code pattern**: wire-format types are compiled into *both* sides of a channel — `HoursTrackerWidget/WidgetBridge.swift` into app + widget extension (App Group + ActivityKit attributes), `Shared/WatchSnapshot.swift` into app + Watch app (WatchConnectivity payload), `Shared/LivePayCurve.swift` into app + widget (the live pay math both read — see §8).

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
| `Managers/Assistant/` | `AssistantEngine` (tool-calling over local data), `AssistantLLMRouter` (BYOK Gemini → OpenAI-compatible fallback, plus `ManagedAssistantLLMProvider` for the free server-funded tier — see §1 and §9). |
| `TelegramFeedbackSender` | Posts to the `submit-feedback` Edge Function (which holds the real Telegram bot token server-side); never talks to the Telegram Bot API directly. |
| `SupportInbox` | Client side of the in-app support chat (`support-chat` Edge Function) — per-install id, works without an account. |
| `AdminAPIClient` | Client side of the admin dashboard/announcements (`admin-api` Edge Function) — every call re-verified server-side against `public.admins`; the client-side `isAdmin` flag only decides whether Settings shows the (otherwise useless) Admin entry. |
| `AnnouncementCenter` | Owns the stable per-install UUID (`stableInstallID()`) shared by `register-device`, `support-chat`, and the managed assistant; receives/display owner push announcements. |
| `WidgetIntegration`, `LiveActivityManager` | Widget timeline/state bridging via App Group; Live Activity lifecycle — see §8 for how this stays numerically in sync with the widget. |
| `WatchConnectivityManager` | Phone ↔ Watch snapshot sync. |
| `LocationReminderManager` | Single CLCircularRegion geofence arrival reminder. |
| `ExportManager`, `FullDataExportManager` | User-facing exports. |
| `PayslipStore`, `ActivityLogStore`, `SessionTombstoneStore` | Payslip records, diagnostic activity log, deleted-session tombstones for merge. |

**State flow**: `Views` → `AppViewModel` (`@MainActor`, owns stores/managers) → `PersistenceManager` (source of truth is local disk; cloud is a mirror/backup, merge-on-sync, never the live store).

**Build system**: **XcodeGen** — edit `project.yml`, run `xcodegen generate`; do not hand-edit the `.xcodeproj`. Swift 5.9, iOS deployment target **17.0**, watchOS **10.0**; builds must use **Xcode 26.x** (App Store requirement as of April 2026). App version: see `project.yml` (never restated here — see Build Versioning); version trains 1.2/1.3/1.5 are permanently closed on App Store Connect — new submissions need a higher marketing version even if it's otherwise a minor update.

## 4. The 5-tab structure

`MainTabView` (in `HoursTrackerApp.swift`) is a single `TabView` with exactly these tabs, in this order — each tagged, each with an `accessibilityIdentifier("tab.<name>")` used by UI tests:

1. **Home** (`tab.home`, `clock.fill`) — clock in/out door button (idle/active/completed states), gross/net toggle, today/week stat cards.
2. **History** (`tab.history`, `list.bullet.rectangle`) — session list, manual entry/edit, Day Type picker (incl. Holiday auto-fill), bulk delete.
3. **Payslips** (`tab.payslips`, `doc.text.viewfinder`) — uploaded payslip library, Smart Scanner review.
4. **Export** (`tab.export`, `square.and.arrow.up`) — quick date pills, mini-receipt preview, "What's included" checklist, PDF/report generation.
5. **Settings** (`tab.settings`, `gearshape.fill`) — see §6.

Switching tabs resets that tab's own navigation stack back to its root (`tabResetTokens`) — returning to a tab never leaves you mid-way down a pushed screen from last time.

## 5. Theme system

Two independent, user-facing customization layers — don't confuse them:

- **`HomeAccentTheme`** (`Utilities/HomeAccentTheme.swift`) — the app-wide tint applied to buttons, toggles, and interactive chrome via `.tint(homeTheme.accent)`. User-selectable from 8 presets; **default is Cyan (`#00E5FF`)**. Presets: Green (`26F273`), Mint (`35E0A8`), Cyan (`00E5FF`, default), Blue (`3B9CFF`), Violet (`9C6BFF`), Pink (`FF5FA8`), Amber (`FFB238`), Red (`FF5A5F`). Persisted as a hex string in `UserDefaults`.
- **`AppBackgroundTheme`** (`Utilities/AppBackgroundTheme.swift`) — the app's background color/gradient, independently user-selectable; default is black (`#000000`).
- **`HomeNeon`** (`Views/HomeVitalityViews.swift`) — a small set of *fixed* (non-user-configurable) accent colors used specifically by the Home screen's neon-glow visual design and a few other "always-positive/always-brand" accents (e.g. the legal consent screen's checkmark icon) — `HomeNeon.accent` is a fixed green, independent of the user's chosen `HomeAccentTheme`. Don't reach for this when you mean the user's theme color.
- The Export tab's quick-pill/gradient accents (`00E5FF`/`26F273`, cyan→green) are hardcoded to match the brand palette rather than following the user's theme — intentional, not a bug.
- `DesignSystem.swift` (`DS` namespace) holds the broader design-token palette (surface colors, semantic state colors like `clockedIn`/`overdue`/`success`, spacing scale, corner-radius scale, animation curves) used across non-Home screens.

## 6. Settings architecture

Settings is a single `Form` (`SettingsView.swift`), **not** a card/ScrollView layout — an earlier ScrollView + custom-card redesign (`SettingsRow`/`SettingsSection`) was tried and then **fully reverted** after it shipped visually broken on physical devices (overlapping rows, empty gaps). `SettingsRow.swift` no longer exists in the codebase; if you ever see it referenced, that reference is stale.

Top-to-bottom, the root `Form` is:

1. **Account section** — sign-in/profile card.
2. **Four group links**, each a `NavigationLink` row (icon + title + one-line summary) into its own `Form`-based sub-page, built by the shared `settingsPage()` helper:
   - **Work & Pay** (`briefcase.fill`) → Workplace & personal details, Pay & hours, Work rules, Payroll & tax.
   - **Reminders** (`bell.badge.fill`) → location arrival reminders, break/shift notification settings.
   - **Privacy** (`lock.shield.fill`) → App Lock, widget pay visibility, Smart Scanner cloud toggle, data safety.
   - **Data & Tools** (`externaldrive.fill`) → cloud sync (if supported), the hidden Admin section (only rendered when `viewModel.isAdmin`), and general tools (activity log, etc.).
3. Language section, About section, Danger Zone (delete all data), Share app.

**The Form-insertion-animation fix**: `Form`/`List` apply an implicit pop-in animation while diffing their content on first render of a pushed screen — rows driven by a condition that resolves after first paint (e.g. `dataGroupPage`'s `if viewModel.isAdmin`) used to visibly flicker in. Every page built by `settingsPage()`, plus `WorkRulesView` and `RemindersView` (which build their own `Form` directly), applies `.transaction { $0.disablesAnimations = true }` to kill this unconditionally. `isAdmin` itself is resolved once at `AppViewModel.init()` (`checkAdminStatus()`), long before Settings can be opened, so in practice it's already settled by the time anyone sees the page — the `disablesAnimations` fix is pure defense-in-depth for any future conditional row.

Avoid `.redacted(reason: .placeholder)` on a boolean condition that's permanently false for most users (e.g. `isAdmin`) — it was tried and produces a permanently-stuck shimmering, unreadable section. Reserve `.redacted` for genuinely transient async values (e.g. the widget-install-count row, which resolves shortly after the page opens).

## 7. Tech stack — what is used

- **Language/UI**: Swift 5.9, SwiftUI (no UIKit screens; UIKit only where APIs demand it), String Catalogs for localization (en/he/ar/ru/th), `os.Logger` for diagnostics (subsystem `com.hourstracker.app`).
- **Apple frameworks**: WidgetKit, ActivityKit (Live Activities, Dynamic Island), CloudKit, Vision + PDFKit (OCR), CoreLocation (geofencing only), WatchConnectivity, PhotosUI/PhotosPicker, LocalAuthentication (Face ID), App Intents (widget buttons, Siri), UserNotifications, os.
- **Third-party**: exactly **one** in the iOS app — `supabase-swift` via SPM (`from: 2.0.0`). Everything else is first-party. The Supabase **backend** (Edge Functions) additionally uses `jsr:@supabase/supabase-js@2` (Deno).
- **Tooling**: XcodeGen, `xcodebuild` CLI builds, Swift Concurrency (async/await, `@MainActor`, Swift 6 strict-concurrency aware).

## 8. Live Activity / Widget sync architecture

The Lock Screen Live Activity, the Dynamic Island, and the Home Screen widget must never show three different numbers for the same running shift. They don't, because all three ultimately read the same `LivePayCurve` (`Shared/LivePayCurve.swift`, compiled into both the app and the widget extension) via `WidgetBridge`'s App Group storage:

- `HoursWidget.swift` computes `let pay = curve?.pay(at: date, net: showsNet) ?? 0` — **no quick-estimate fallback**: if the curve isn't there yet, the shift just hasn't started pricing, so it reads `0` rather than a different number from a different formula.
- `LiveActivityManager.makeState(...)` was fixed (2026-11-08) to match that exactly: it used to fall back to `WidgetBridge.estimatePay(...)` (a different, cheaper formula) whenever its `curve` parameter was `nil` or stale. It now mirrors the widget's `matchingCurve?.pay(at:) ?? 0` pattern — same curve, same `pay(at:net:)` call, same zero-fallback — on both reads (`paidSeconds` and `pay`), including `payIsNet` only being true when there's an actual matching curve.
- `pay(at:)` is piecewise-linear, so the app only needs to re-push the Live Activity roughly every 60s (and on any break/settings change) for it to stay accurate between pushes — it's not an approximation, it's the tier's exact slope.

**If you ever touch pay-rendering code in `LiveActivityManager`, `HoursWidget.swift`, or `LivePayCurve`, keep this invariant**: both consumers resolve price from the same curve with the same no-fallback rule. A quiet "estimate when the curve's missing" fallback in only one of them is exactly the kind of bug that's easy to introduce and easy to miss, because it only shows up as "the widget and the Lock Screen briefly disagree."

## 9. Backend, database, auth

- **Backend: Supabase** (hosted, project ref `rocjprrvrvmtisxnvopg`). Project URL + publishable anon key live in `HoursTracker/Utilities/SupabaseConfig.swift` and `HoursTracker/Utilities/TelegramFeedbackConfig.swift`, and **are meant to ship in the client** — security is enforced **server-side**, either by Postgres RLS (for tables the app's Swift client touches directly) or by server-side checks inside Edge Functions (for everything else, described below).
- **Database: PostgreSQL 17** (Supabase). Tables the app's client touches *directly* with the user's own session (RLS-scoped to `auth.uid()`, verified via `pg_policies` on the live project):
  - `user_backups` — one row per user: `user_id`, `payload` (**JSONB** `{settings, sessions[]}`, the whole restore set), `app_version`. Policies: `auth.uid() = user_id` for select/insert/update.
  - `profiles` — `id` (= auth user id), `full_name`, `family_name`. Policies: `auth.uid() = id` for select/insert/update.
  - Supabase Auth's own tables back email accounts.
- **Tables that only Edge Functions (service role) touch** — RLS **enabled with zero policies** on every one of these, which is correct by design: it means the `anon`/`authenticated` roles get no access at all, and authorization is enforced entirely in the Edge Function code (audited 2026-11-08, see §9b):
  `devices`, `admins`, `announcements`, `announcement_targets`, `request_rate_limit`, `feedback_rate_limit`, `ai_usage`, `ai_global_usage`, `app_config`, `support_threads`, `support_messages`, `support_auto_replies`, `admin_audit_log`.
- **Edge Functions** (`supabase/functions/`, Deno + `jsr:@supabase/supabase-js@2`):

  | Function | `verify_jwt` | Purpose |
  |---|---|---|
  | `register-device` | false | Device registry upsert (push token, language, Watch/widget flags); per-IP + per-device rate-limited. |
  | `ai-assist` | false | Managed/free AI tier. Validates `deviceId` as a real UUID, rate-limits by IP (20/hour) *and* by `consume_ai_quota` (3/day, 10/week per device, 800/day global). |
  | `support-chat` | false | User side of in-app support chat, keyed by per-install UUID; `send` rate-limited 10/hour, `list`/`status` rate-limited 60/hour. |
  | `submit-feedback` | true | Proxies free-text feedback + optional attachment to Telegram; per-IP rate-limited; length-capped; sanitizes filename/caption before building the multipart body. |
  | `admin-api` | false | Owner announcement composer/dashboard. Verifies session via `auth.getUser`, then checks `public.admins`, on every call. |
  | `support-admin` | false | Owner support inbox. Same admin check as `admin-api`. |
  | `admin-ops` | false | Owner kill-switches (`ai_enabled`/`chat_enabled`) + audit log. Same admin check. |
  | `delete-account` | true | Deletes the caller's own account. Identity comes *only* from the verified session token, never the request body. |

- **Auth: Supabase Auth (GoTrue)** — email + password sign-up, **8-digit email OTP** confirmation (the project's dashboard OTP-length setting is 8; the app enforces exactly 8 digits — keep them in sync). Error handling uses the SDK's structured `AuthError` `errorCode` (e.g. `.otpExpired`), **never** substring matching on `localizedDescription`.
- **Secondary cloud**: Apple **CloudKit private database** (container `iCloud.com.hourstracker.app`), entitlement-gated and off in personal-team builds; merge-based sync with tombstones.

### 9b. Backend security rules (audited and enforced 2026-11-08)

These rules were derived from a full audit of every Edge Function, migration, and the live project's RLS/advisories. Apply them to any new Edge Function:

1. **Never trust a client-supplied identifier as if it were authenticated.** Every per-install `deviceId` the app sends (to `register-device`, `support-chat`, `ai-assist`) must be validated as a real UUID (`^[0-9a-f]{8}-...$`) *and* rate-limited by IP, not just by the claimed id — an id alone is a free, unlimited-supply token an attacker can mint per request. (`ai-assist` was found missing both checks and fixed; it had no IP limit and accepted any 16–64 char string, which let anyone holding the public anon key bypass the per-device quota entirely and exhaust the shared daily Gemini cap.)
2. **Every read action needs a rate limit, not just writes.** `support-chat`'s `list`/`status` actions had none (only `send` did), which let anyone free-probe arbitrary deviceId guesses. Reused the existing generic `check_rate_limit(bucket, key, limit, window_minutes)` RPC — don't invent a new mechanism per function.
3. **Admin/owner endpoints verify `auth.getUser(token)` then check `public.admins` on every single call** — `admin-api`, `support-admin`, `admin-ops` all do this. The client-side `isAdmin` flag (`AdminAPIClient`) only controls whether a UI entry point is shown; it grants no actual access.
4. **Never splice client-supplied strings into a raw hand-built request body** (multipart or otherwise) without stripping CR/LF and the delimiter you're using. `submit-feedback`'s `documentName`/`caption` were spliced unescaped into a multipart body sent to Telegram — a filename containing a quote or CRLF could have forged extra form fields (e.g. `chat_id`). Fixed by stripping `\r\n` and escaping `"`.
5. **Cap every input length server-side**, even if the shipping app already limits it client-side — the endpoint is reachable directly by anyone holding the public anon/publishable key, by design. `submit-feedback` had no caps at all before the 2026-11-08 fix.
6. **Identity (user id, email) always comes from the verified session token** (`supabase.auth.getUser(token)`), never from the request body — `delete-account`, `register-device`, `support-chat` all follow this; keep it true for anything new.
7. **A table only the service role touches should have RLS enabled with *zero* policies** — that's the correct pattern (it's not a misconfiguration the linter should scare you into "fixing" with policies), as long as every Edge Function that reaches it enforces authorization in code per the rules above.
8. **Don't deploy an Edge Function without committing its source.** `ai-assist` and `admin-ops` existed live on Supabase but were never committed to this repo until the 2026-11-08 audit — always add new functions under `supabase/functions/<name>/index.ts` before or immediately after deploying.
9. Supabase's project-level "Leaked Password Protection" (Authentication → Policies, HaveIBeenPwned check) is currently **off** — recommended to turn on, zero downside, not yet done (dashboard-only setting, not code).

## 10. Connections (network & integrations)

| Channel | Transport | Purpose |
|---|---|---|
| Supabase (REST/PostgREST via supabase-swift) | HTTPS | Auth, `user_backups` upsert/select, `profiles` upsert/select |
| Supabase Edge Functions | HTTPS | `register-device`, `ai-assist`, `support-chat`, `submit-feedback`, `admin-api`, `support-admin`, `admin-ops`, `delete-account` — see §9 |
| Gemini API / any OpenAI-compatible endpoint | HTTPS REST | BYOK assistant + optional scanner LLM assist; keys user-supplied, stored in **Keychain** (`KeychainStore`); router falls back Gemini-first. The managed assistant's Gemini key lives server-side only (`GEMINI_API_KEY` secret on `ai-assist`), never in the app. |
| Telegram Bot API (via `submit-feedback`) | HTTPS (server-side JSON `sendMessage`, multipart `sendDocument`) | In-app Contact Support feedback → developer's Telegram channel; bot token never ships in the app |
| APNs | HTTPS/HTTP2 (server-side, from `admin-api`/`support-chat`/`support-admin`) | Owner announcements, support-reply pushes |
| CloudKit | Apple framework | Optional iCloud private-DB backup/sync |
| WatchConnectivity | Bluetooth/on-body | Phone ↔ Watch shift snapshots |
| App Group (`group.com.hourstracker.app` pattern — see entitlements) | Local IPC | App ↔ widget shared state (incl. the Live Activity's `LivePayCurve`); widget buttons deep-link back via `hourstracker://` |

**Secrets policy (important)**:
- `LocalSecrets.swift` holds nothing real — it is committed with empty placeholders and the real values are kept out of git via `git update-index --skip-worktree`. Never commit real values there; the repo is **public** and one token was historically leaked and had to be rotated.
- `Secrets.xcconfig` carries build-setting-level secrets via `$(VAR)` substitution into Info.plist; committed with empty values.
- LLM API keys the *user* supplies never touch disk files — **Keychain only**. The managed assistant's and Telegram's secrets live only as Supabase Edge Function secrets (`supabase secrets set`), never committed, never in chat.
- `SupabaseConfig.publishableKey` and `TelegramFeedbackConfig.supabaseAnonKey` are **intentionally public** — see §9.

## 11. How it works (end-to-end data flow)

1. **Launch**: `HoursTrackerApp` → `AppViewModel` loads sessions + settings from `PersistenceManager` (JSON in Documents). Load failures are triaged (`missing` / `temporarilyUnavailable` / `corruptQuarantined`) so a transient read error can never wipe data. `checkAdminStatus()` resolves `isAdmin` once here, before Settings can be opened.
2. **Clock in/out**: UI (or widget button via App Intent + deep link, or Watch) mutates `AppViewModel` state → `PersistenceManager` writes JSON → side effects fire: Live Activity start/update (via the shared `LivePayCurve`, §8), widget timeline reload (via App Group), Watch snapshot push, geofence arming, optional mirrored cloud write through `SyncingPersistenceStore`.
3. **Sync (account backup)**: signed-in user taps Sync (or mutation occurs with `SyncingPersistenceStore` active) → `SupabaseAccountSyncManager.uploadBackup` encodes `{settings, sessions}` as ISO-8601 JSON → upserts into `user_backups` (RLS scopes it to `auth.uid()`), and refreshes `profiles`. Download reverses this and merges into the local store. CloudKit path (if enabled) does field-level merge with tombstones instead.
4. **Scanner**: photo/PDF → Vision OCR (or PDFKit text) → candidate shift rows → optional LLM cleanup via `AssistantLLMRouter`-style provider chain → user reviews confidence-flagged drafts → conflict check against existing sessions → import.
5. **Pay math**: `WorkSession` list + `WorkplaceSettings` → `OvertimeCalculator` / `IsraeliTaxEstimator` / `TaxCreditPointsCalculator` (+ `IsraeliHolidays`) → live pay cards, history breakdowns, and export documents. Estimation only — clearly labeled.
6. **Assistant**: user question + local data summary → `AssistantEngine` plans tool calls (reads sessions/settings locally) → `AssistantLLMRouter` asks the BYOK key (Gemini, falls back to OpenAI-compatible) or, if no key is set, the managed `ai-assist` Edge Function (quota-limited, see §9). With neither available it reports itself as not set up rather than pretending.
7. **Feedback**: `ContactSupportSheet` → `TelegramFeedbackSender` → `submit-feedback` Edge Function (rate-limited, length-capped, sanitized — §9b) → Bot API → developer's Telegram channel. Separately, `SupportInbox` gives a persistent two-way chat via `support-chat`/`support-admin`, keyed by the device's stable install id, with no account required.
8. **Widgets/Live Activities**: extension reads shared state from the App Group, renders timelines, interactive buttons run App Intents that mutate the app's store and `WidgetCenter`-reload; deep links (`hourstracker://`) route back into specific screens. The Live Activity and the widget both price the shift from the same `LivePayCurve` — see §8.

## Legally Sensitive Fields

Rest days change the pay premium; never bind `WeekPattern` to them.

- `WorkplaceSettings.restDayWeekday` / `secondRestDayWeekday` are the **legal weekly rest day(s)** (Shabbat, Friday or Sunday depending on the worker). Work on them is paid at a premium, so they are pay inputs — not "days I usually don't work".
- The onboarding's week pattern (5 days / 6 days / varies / custom days) and `weeklyGoalHoursDisplayOnly` are **display-only** (`DisplayPreferences`, `Models/OnboardingSetup.swift`). They drive previews and goals only and must never be copied into rest days, `weeklyStandardHours` (the legal overtime threshold) or any other pay input. `OnboardingSetupTests.testDisplayOnlyPreferencesNeverReachPayMath` pins this.
- Any new "convenience" question that looks like a schedule (days off, expected hours, shift type) follows the same rule: store it as a display preference; change pay inputs only through Settings, where the user sees the legal meaning.

## Display vs. Calculation Separation

- The pay engine keeps Shabbat/holiday hours in the "regular" bucket (base 150%, then 175%/200% for overtime) — see `OvertimeCalculator.tiers(for:)`.
- `PayTier` (`Models/PayTier.swift`, display layer) reads the day type and shows the real rate.
- Never assume `regularHours` == 100%. Always go through `PayTier` when showing rates, tier colours or tier labels. `DaySummaryTests.testShabbatShiftShowsAllHoursAt150Percent` pins this.

## Number Entry in Hebrew/Arabic

- A SwiftUI `TextField` for amounts stored the typed digits but drew nothing in Hebrew/Arabic (only the caret), with or without a forced `.leftToRight` (BUG #1).
- Use `AmountField` (`Views/AmountField.swift`) for amount entry: the real `TextField` stays for input, focus and VoiceOver with clear text, and the digits and caret are drawn with `Text` on top.
- `OnboardingRTLUITests` checks the digits are actually drawn (pixels), not only stored.

## Build Versioning

- Version and build number come from `project.yml` → `settings.base.MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` — one place for the app, widget and Watch. Every Info.plist reads them as `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`; App Store Connect rejects an upload whose extensions don't match the app.
- Never hard-code them in Swift or markdown.
- `Info.plist` inherits them from `project.yml` at generate time (`xcodegen generate`).
- Any text that shows a version must read it from `Bundle.main` (see `AboutSheet.versionString`).

## Quick facts

- **Bundle IDs**: `com.hourstracker.app` (+ `.widget`, `.watchkitapp`, `.tests`, `.uitests`). Team `FQUC6DU87N`.
- **Targets**: app, widget extension, watchOS app, unit tests, UI tests.
- **Minimums**: iOS 17.0 / watchOS 10.0. Build with Xcode 26.x.
- **Testing**: `xcodebuild -project HoursTracker.xcodeproj -scheme <scheme>` for app and test targets; unit tests cover persistence, calculators, sync merge logic. UI tests include screenshot/QA automation (`ScreenshotTests.swift`, `DesignQATests.swift`, `MarketingShotsTests.swift`, `SettingsQATests.swift`) driven by `UITEST_*` launch arguments handled in `AppDelegate.swift` (DEBUG-only).
- **Local debugging**: run `xcodegen generate` after editing `project.yml`; fill `LocalSecrets.swift` locally (skip-worktree) for feedback; widget data needs the App Group entitlements intact.
- **Known sharp edges**: (1) never let a transient store-read failure become an empty-store overwrite; (2) Supabase OTP length (dashboard) must match the app's 8-digit entry; (3) don't add background-location modes (App Store rejection history); (4) version trains below 1.6 are closed on App Store Connect; (5) never commit real Telegram/Gemini/APNs secrets — rotate immediately if leaked; (6) `HoursTrackerWatch/Resources/Localizable.xcstrings` must stay a symlink — see §3; (7) the widget and the Live Activity must always price a shift from the same `LivePayCurve` with no silent fallback — see §8; (8) any new Edge Function follows the rules in §9b.
