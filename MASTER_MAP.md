# MASTER_MAP.md — HoursTracker System Prompt for AI Agents

> Give this file to any AI agent (Gemini, DeepSeek, ChatGPT, Claude — a fresh session or a different model) before it touches this codebase. It is generated from the actual state of the repository, not from memory or prior docs. Last generated: 2026-11-08.

---

## Section 0: The 10 Commandments

Non-negotiable. Breaking any of these is a regression, not a style choice.

1. **No hardcoded user-facing text.** Every string the user can see goes through `L10n` → `Localizable.xcstrings`, translated in all 5 languages (en, he, ar, ru, th).
2. **No hardcoded colors.** Use `HomeAccentTheme.shared.accent` (user theme), `AppBackgroundTheme.shared.background` (user background), `HomeNeon` (fixed brand accents), or `DesignSystem`'s `DS` tokens — never a raw `Color(hex:)`/`Color(red:green:blue:)` literal dropped into a view ad hoc.
3. **`OvertimeCalculator` is the only place pay/overtime math happens.** Never recompute tiers, rates, or totals by hand in a View or ViewModel — go through `OvertimeCalculator` → `PayTier` for display.
4. **No `AnyView` wrapping a `NavigationLink`'s destination.** It was removed everywhere (`// NO AnyView` comments mark the cleanup in `SettingsView.swift`) — it breaks navigation identity/animation. Still fine for wrapping ordinary `Section` body content, not a destination.
5. **Settings pages are `Form`/`Section`, never `ScrollView` + custom card.** A ScrollView+card redesign (`SettingsRow`/`SettingsSection`) was tried and fully reverted after shipping visually broken on real devices. `SettingsRow.swift` does not exist — if you see it referenced, that reference is stale.
6. **`LivePayCurve` (`HoursTracker/Shared/LivePayCurve.swift`) is the only source of a running shift's live pay.** The widget and the Live Activity must both read it with the exact same no-fallback rule (`curve?.pay(at:net:) ?? 0`) — see §4.
7. **`HoursTrackerWatch/Resources/Localizable.xcstrings` must stay a symlink** to `../../HoursTracker/Resources/Localizable.xcstrings`. It has been accidentally materialized into an independent file before and silently dropped out of sync (see §4) — never hand-edit a Watch-local copy.
8. **Every Supabase Edge Function validates input, rate-limits by IP, and admin endpoints re-check `public.admins` server-side on every call.** See §5 for the full rule set.
9. **Never block the main thread with real computation inside SwiftUI's render/`.onChange` path.** Anything that does real work across a session list (`OvertimeCalculator.aggregate`, etc.) goes on `Task.detached`, with cancellation to avoid stale-result races. See §4 (Export freeze).
10. **All unit tests must pass (currently 484/484), and `xcodegen generate` must run after any file add/remove** before a change is considered done.

---

## Section 1: App Overview & Tech Stack

**What it is**: a worker-first hours & pay tracking app for hourly employees in Israel, localized in 5 languages (English, Hebrew, Arabic, Russian, Thai — Hebrew/Arabic are RTL). Clock in/out, manual history editing, a timesheet scanner (Vision OCR + optional LLM assist), Israeli payroll math (overtime tiers, tax estimator, tax credit points, holidays), payslip library, exports, Home Screen widgets + Live Activity + Apple Watch companion, optional cloud account/backup, an in-app AI assistant (BYOK or a free rate-limited managed tier), and in-app support chat.

**Tech stack**:
- **UI**: SwiftUI only (iOS 17+ deployment target, watchOS 10+), no UIKit screens. String Catalogs (`.xcstrings`) for localization.
- **Build**: XcodeGen (`project.yml` → generates `.xcodeproj`; never hand-edit the generated project). Swift 5.9, Xcode 26.x required.
- **Backend**: Supabase — Postgres 17, Supabase Auth (email + 8-digit OTP), Edge Functions (Deno + `jsr:@supabase/supabase-js@2`).
- **Apple frameworks**: WidgetKit, ActivityKit (Live Activity / Dynamic Island), CloudKit (optional secondary sync), Vision + PDFKit (OCR), CoreLocation (single-geofence only, no background tracking), WatchConnectivity, LocalAuthentication (Face ID), App Intents, UserNotifications.
- **Third-party in the app**: exactly one SPM package — `supabase-swift`.
- **Concurrency**: Swift Concurrency throughout (async/await, `@MainActor`, `Task.detached` for off-main-thread work).

**High-level architecture (text diagram)**:

```
                         ┌─────────────────────────┐
                         │        SwiftUI Views      │
                         │  (Home/History/Payslips/  │
                         │   Export/Settings tabs)    │
                         └────────────┬───────────────┘
                                      │ observes / mutates
                                      ▼
                         ┌─────────────────────────┐
                         │   AppViewModel (@MainActor)│◄──── App Intents (widget buttons,
                         │  + LivePay / Watch / …ext.  │       Siri) mutate this too
                         └────────────┬───────────────┘
                     ┌────────────────┼─────────────────────┐
                     ▼                ▼                     ▼
         ┌────────────────────┐ ┌────────────┐   ┌───────────────────────┐
         │  PersistenceManager │ │ LivePayCurve│   │ SyncingPersistenceStore│
         │ (local JSON, source  │ │ (Shared/)   │   │ → SupabaseAccountSync  │
         │  of truth on disk)   │ │ shared by:  │   │   Manager (user_backups,│
         └──────────┬───────────┘ │ - Widget    │   │   profiles — RLS'd)    │
                     │            │ - Live      │   └───────────────────────┘
                     │            │   Activity  │             │
                     ▼            └─────┬───────┘             ▼ optional
         ┌────────────────────┐         │             ┌───────────────────┐
         │ OvertimeCalculator  │         │             │  CloudKit private  │
         │ + IsraeliTaxEstimator│        │             │  DB (entitlement-  │
         │ (the ONLY pay math) │         │             │  gated)            │
         └────────────────────┘         │             └───────────────────┘
                                         ▼
                         ┌───────────────────────────────┐
                         │ App Group (shared storage) ───►│ Widget extension /
                         │                                │ Live Activity (ActivityKit)
                         └───────────────────────────────┘
                                         │ WatchConnectivity
                                         ▼
                                 Apple Watch app

         ┌──────────────────────────────────────────────────────────┐
         │ Supabase (hosted, project ref rocjprrvrvmtisxnvopg)       │
         │  Edge Functions (service-role, rate-limited, admin-checked)│
         │   register-device · ai-assist · support-chat ·            │
         │   submit-feedback · admin-api · support-admin ·           │
         │   admin-ops · delete-account                               │
         │  Postgres: user_backups/profiles (RLS→auth.uid()),        │
         │   everything else (devices, admins, ai_usage, support_*,  │
         │   …) RLS-enabled-zero-policy, service-role-only           │
         └──────────────────────────────────────────────────────────┘
```

---

## Section 2: Golden Rules (Detailed)

**1. No hardcoded user-facing text.**
*Why*: the app is shipped in 5 languages; a literal string shows the wrong language to 4/5 of users, or (for RTL) breaks layout direction expectations. This has happened twice for real — `SettingsView.swift`'s "Work & Pay" footer and `HistoryView.swift`'s holiday banner both shipped with literal Hebrew text visible to English/Arabic/Russian/Thai users, fixed 2026-11-08 (see §4).
*How to verify*: grep the file you're touching for any Hebrew/Arabic/Cyrillic/Thai Unicode ranges in a `Text(...)` call, or any plain English string literal that isn't a format specifier, symbol name, or debug-only/admin-only label. Every real string should resolve through `L10n.xxx` or `t("key")`.

**2. No hardcoded colors.**
*Why*: there are three independent, deliberately distinct color systems (user accent, user background, fixed brand neon) — picking the wrong one either ignores the user's customization or accidentally recolors something that should always read as "success/brand," not whatever the user picked.
*How to verify*: search the diff for `Color(hex:` or `Color(red:` outside `HomeAccentTheme.swift`, `AppBackgroundTheme.swift`, `HomeVitalityViews.swift` (defines `HomeNeon`), and `DesignSystem.swift`. The Export tab's cyan/green gradient (`00E5FF`/`26F273`) is an intentional exception — it's the fixed brand palette, not the user's theme.

**3. `OvertimeCalculator` is the only place pay/overtime math happens.**
*Why*: Israeli overtime law has specific tier rules (125%/150%, rest-day premiums, sick-day streak pricing, daily gas allowance apportioning) that are easy to get subtly wrong if reimplemented. `OvertimeCalculator.tiers(for:)` keeps Shabbat/holiday hours in the "regular" bucket at 150% base, not literally "regular" — a naive reimplementation almost always gets this backwards.
*How to verify*: any new pay-related UI should call `OvertimeCalculator.aggregate(...)` or read from `PayTier`, never sum `WorkSession.effectiveHours * hourlyRate` directly. `DaySummaryTests.testShabbatShiftShowsAllHoursAt150Percent` pins this.

**4. No `AnyView` wrapping a `NavigationLink` destination.**
*Why*: `AnyView` erases view identity, which breaks SwiftUI's diffing/animation assumptions for navigation — this was an actual, diagnosed bug category during the Settings redesign work.
*How to verify*: `grep -n "AnyView" HoursTracker/Views/SettingsView.swift` — the remaining `AnyView(...)` usages wrap plain `Section` *body content* (fine, not a destination), never a `NavigationLink { AnyView(...) }`. Look for `// NO AnyView` comments marking where this was deliberately removed.

**5. Settings pages are `Form`/`Section`, never `ScrollView` + custom card.**
*Why*: the card/ScrollView rewrite (`SettingsRow`, `SettingsSection`) shipped with real, physical-device-confirmed bugs — overlapping rows, empty gaps — and was fully reverted. Re-attempting it without new evidence just reintroduces the same bug class.
*How to verify*: `find . -iname "SettingsRow.swift"` should return nothing. Settings and all its sub-pages (`WorkRulesView`, `RemindersView`, and every page built by `settingsPage()`) use `Form { Section { ... } }`.

**6. `LivePayCurve` is the only source of a running shift's live pay.**
*Why*: the widget, the Live Activity, and the Home screen must never show three different numbers for the same shift. `HoursWidget.swift` computes `curve?.pay(at:net:) ?? 0` with **no quick-estimate fallback** — if the curve isn't available, it shows `0`, not a cheaper approximation. `LiveActivityManager` used to fall back to `WidgetBridge.estimatePay(...)` (a different formula) when its curve was stale/missing; that mismatch was the actual root cause of a real numeric-disagreement bug, fixed 2026-11-08 by making `LiveActivityManager.makeState(...)` mirror the widget's exact `matchingCurve?.pay(at:) ?? 0` pattern.
*How to verify*: any code path that prices a *running* shift should resolve a `LivePayCurve` and apply the same "no curve → 0, don't estimate" rule the widget uses — never add a second formula as a fallback.

**7. `HoursTrackerWatch/Resources/Localizable.xcstrings` must stay a symlink.**
*Why*: Xcode's String Catalog compiler silently produces an **empty** compiled catalog for a target that references a catalog outside its own directory tree — this is why the symlink exists at all (fixing an earlier real bug where the Watch app showed raw L10n keys instead of text). Xcode's String Catalog *editor* is known to materialize that symlink into an independent real file on save; once that happens, every string added to the main catalog afterward silently never reaches the Watch app. This actually happened — found and fixed 2026-11-08, after the materialized copy had drifted to be missing Thai on 1195 of 1213 keys.
*How to verify*: `readlink HoursTrackerWatch/Resources/Localizable.xcstrings` should print `../../HoursTracker/Resources/Localizable.xcstrings`. If it errors (not a symlink), the fix is `rm` the regular file and `ln -s ../../HoursTracker/Resources/Localizable.xcstrings HoursTrackerWatch/Resources/Localizable.xcstrings` — never hand-copy strings into a materialized duplicate.

**8. Supabase Edge Function security rules.**
See §5 — this commandment is expanded there in full since it's a checklist of its own.

**9. Never block the main thread with real computation in SwiftUI's render/`.onChange` path.**
*Why*: `ExportView` used to call `OvertimeCalculator.aggregate(...)` synchronously inside `updatePreview()`, triggered on every `.onChange` of the date range/filters. Rapid picker dragging fired this repeatedly in quick succession, starving the gesture recognizer of main-thread time long enough to trip iOS's "Gesture: System gesture gate timed out" watchdog — a real, confirmed freeze, not a hypothetical. Fixed by moving the aggregate call to `Task.detached(priority: .userInitiated)`, with the prior task cancelled before each new one starts so a slow result for an already-superseded filter can never land after (and overwrite) a newer one.
*How to verify*: any `.onChange` handler that triggers a calculation over the full session list (not a handful of already-cached values) should hop off `@MainActor` via `Task.detached`, write the result back via `await MainActor.run { }`, and check `Task.isCancelled` before writing.

**10. All 484 unit tests must pass; run `xcodegen generate` after file changes.**
*Why*: self-explanatory — a green test suite is the only cheap, repeatable confirmation that a change didn't regress persistence, calculators, or sync-merge logic; a stale `.xcodeproj` (not regenerated after adding/removing a file) causes confusing "file not found" or "works in one scheme but not another" failures that have nothing to do with the actual code change.
*How to verify*: `xcodebuild -project HoursTracker.xcodeproj -scheme HoursTracker -destination '...' -only-testing:HoursTrackerTests test` and check the tail for `Executed 484 tests, with 0 failures`.

---

## Section 3: Exhaustive File Routing Table

| Feature / Concept | File(s) |
|---|---|
| App entry / 5-tab structure | `HoursTracker/HoursTrackerApp.swift` (`MainTabView`), `HoursTracker/AppDelegate.swift` |
| Central state owner | `HoursTracker/ViewModels/AppViewModel.swift` + extensions `AppViewModel+LivePay.swift`, `AppViewModel+Watch.swift`, `AppViewModel+Workplaces.swift` |
| App Lock (Face ID) | `HoursTracker/ViewModels/AppLockController.swift`, `HoursTracker/Views/AppLockView.swift`, `Utilities/AppLockPreference.swift`, `Utilities/BiometricAuthenticating.swift` |
| **Home tab** | `Views/HomeView.swift`, `HomeGreetingRow.swift`, `HomeRateCard.swift`, `HomeStatCard.swift`, `HomeVitalityViews.swift` (defines `HomeNeon`), `HomeThemePickerSheet.swift`, `GrossNetSwitch.swift`, `ForgotClockInSheet.swift`, `PayCardView.swift` |
| **History tab** | `Views/HistoryView.swift` (incl. `holidayBanner`), `HistoryDateBadge.swift`, `HistoryPayBreakdownSheet.swift`, `ManualEntryView.swift`, `ShiftDetailSheet.swift`, `DaySummarySheet.swift`, `WorkedDaysBadge.swift`, `WorkplaceSwitcher.swift`; period math in `Utilities/HistoryPeriodHelper.swift` |
| **Payslips tab** | `Views/PayslipsTabView.swift`, `PayslipLibraryView.swift`, `PayslipDetailView.swift`, `PayslipUploadReviewView.swift`, `BlankTimesheetEntryView.swift`; `ViewModels/PayslipLibraryViewModel.swift`, `PayslipUploadViewModel.swift`; `Managers/PayslipStore.swift`; model `Models/PayslipRecord.swift` |
| **Export tab** | `Views/ExportView.swift` (quick pills, mini-receipt, "What's included", `updatePreview()` off-main-thread aggregate); `Managers/ExportManager.swift`, `FullDataExportManager.swift`; `Utilities/ExportCopy.swift`, `ExportLayout.swift`, `ExportSanitizer.swift`, `ExportTempFileStore.swift`; `Models/ExportLanguage.swift` |
| **Settings — root** | `Views/SettingsView.swift` (`Form` → account section, 4 group links, language/about/danger-zone/share sections) |
| **Settings — Work & Pay group** | `SettingsView.swift`'s `workGroupPage` (inline: Workplace & personal details, Pay & hours, Payroll & tax rows) + `Views/WorkRulesView.swift` (its own `Form`) + `Views/EmploymentSettingsView.swift` (`EmploymentSettingsRows`, `EmploymentPensionRows`, `EmploymentMoveSheet`) + `Views/HolidaysEditorView.swift` (`HolidaysSettingsLink`, `HolidaysEditorView`) |
| **Settings — Reminders group** | `Views/RemindersView.swift` (its own `Form`: location arrival reminders, break/shift notification settings) |
| **Settings — Privacy group** | `SettingsView.swift`'s `privacyGroupPage` (App Lock, widget pay visibility, Smart Scanner cloud toggle, data safety); `Views/DataSafetyViews.swift` |
| **Settings — Data & Tools group** | `SettingsView.swift`'s `dataGroupPage` (sync rows, admin-only section gated on `viewModel.isAdmin`, tools/activity log); `Views/ActivityLogView.swift`; `Managers/ActivityLogStore.swift` |
| Account / Auth | `Views/AccountSheet.swift`; `Managers/SupabaseAuthManager.swift`, `SupabaseAccountSyncManager.swift`, `AccountProfileStore.swift`; `Utilities/SupabaseConfig.swift` |
| Legal consent | `Views/LegalConsentView.swift`, `TermsOfUseView.swift`, `PrivacyPolicyView.swift`; `Managers/LegalConsent.swift` |
| Onboarding / User Guide | `Views/OnboardingView.swift`; `Views/UserGuideSheet.swift` (9-slide guide; slide copy is hardcoded per-language Swift literals in its own `GuideCopy` struct — **not** in `Localizable.xcstrings**, by design) |
| **Pay math (the only place)** | `Models/OvertimeCalculator.swift`, `IsraeliTaxEstimator.swift`, `TaxCreditPointsCalculator.swift`, `PayTier.swift`, `IsraeliHolidays.swift`, `HolidayCustomization.swift`; formatting in `Utilities/PayFormatter.swift` |
| Session / settings models | `Models/WorkSession.swift`, `WorkplaceSettings.swift`, `Workplace.swift`, `AdditionalWorkplace.swift`, `EmploymentInfo.swift`, `ShiftKind.swift`, `ShiftSchedule.swift`, `LeaveDay.swift`, `MaritalStatus.swift`, `OnboardingSetup.swift`, `HomeStatGoals.swift` |
| Local persistence | `Managers/PersistenceManager.swift`, `SyncingPersistenceStore.swift`, `SessionTombstoneStore.swift`; `Utilities/CorruptFileQuarantine.swift`, `ProtectedFileWriter.swift`, `CloudWriteQueue.swift` |
| CloudKit sync | `Managers/CloudKitSyncManager.swift`; `Utilities/CloudSyncPreference.swift` |
| **Live Activity** | `Managers/LiveActivityManager.swift` (start/update/end, `makeState(...)`); shared math in `Shared/LivePayCurve.swift` (compiled into app **and** widget) |
| **Widget extension** | `HoursTrackerWidget/HoursWidget.swift`, `LockScreenWidget.swift`, `LiveActivityViews.swift`, `WidgetActions.swift`, `WidgetBridge.swift` (App Group bridge, compiled into app + widget), `WidgetStrings.swift`, `ShiftIntents.swift` (App Intents, also compiled into the main app target) |
| Widget integration (app side) | `Managers/WidgetIntegration.swift`, `WidgetNudge.swift`; `Views/WidgetInstallGuideView.swift` |
| **Watch app** | `HoursTrackerWatch/HoursTrackerWatchApp.swift`, `WatchMainTabView.swift`, `WatchHomeView.swift`, `WatchHistoryView.swift`, `WatchExportView.swift`, `WatchSettingsView.swift`, `WatchSessionStore.swift`, `WatchColorHex.swift` |
| Watch connectivity (phone side) | `Managers/WatchConnectivityManager.swift`; `Shared/WatchSnapshot.swift` (compiled into app + Watch) |
| Scanner (OCR + LLM) | `Managers/TimesheetScannerManager.swift`, `Managers/Scanner/*` (Gemini/OpenAI-compatible/local-heuristic providers + router + validators); `Views/TimesheetScannerView.swift` |
| BYOK + managed AI assistant | `Managers/Assistant/*` (`AssistantEngine`, `AssistantLLMRouter`, `GeminiAssistantLLMProvider`, `OpenAICompatibleAssistantLLMProvider`, `ManagedAssistantLLMProvider`); `ViewModels/AssistantChatViewModel.swift`; keys in `Utilities/KeychainStore.swift` |
| In-app support chat | `Views/SupportChatSheet.swift`, `SupportReplyBanner.swift`; `Managers/SupportInbox.swift`, `LocalSupportAttachmentStore.swift`; `Views/ContactSupportSheet.swift`; `Managers/TelegramFeedbackSender.swift`, `Utilities/TelegramFeedbackConfig.swift` |
| Admin / owner tools | `Views/AdminDashboardView.swift`, `AdminControlRoomView.swift`, `AdminSupportInboxView.swift`, `AdminAutoRepliesView.swift`; `Managers/AdminAPIClient.swift` |
| Push announcements | `Managers/AnnouncementCenter.swift` (owns `stableInstallID()`); `Views/AnnouncementBanner.swift` |
| **Localization** | `Utilities/L10n.swift` (all accessors), `Resources/Localizable.xcstrings` (single source of truth — the Watch copy is a **symlink**, see §0/§2), `Utilities/AppLocale.swift` (`AppLocale.tr(key)`, RTL/layout-direction resolution), `Utilities/AppLanguagePreference.swift` |
| Theme system | `Utilities/HomeAccentTheme.swift` (user accent, default Cyan `00E5FF`), `Utilities/AppBackgroundTheme.swift` (user background), `Views/HomeVitalityViews.swift` (`HomeNeon`, fixed brand green), `Utilities/DesignSystem.swift` (`DS` tokens) |
| Notifications / reminders | `Managers/ShiftReminderScheduler.swift`, `BreakReminderScheduler.swift`, `ShiftSummaryNotifier.swift`, `LocationReminderManager.swift`; `Utilities/NotificationPreferences.swift` |
| App update prompt / What's New | `Views/UpdatePromptView.swift`, `WhatsNewView.swift`; `Managers/UpdateReminderCenter.swift`, `WhatsNewCenter.swift` |
| Siri / Shortcuts | `Intents/SiriIntents.swift`, `SiriReport.swift`, `HoursTrackerShortcuts.swift` |
| Secrets / config | `Config/LocalSecrets.swift` (empty placeholders, skip-worktree), `Config/Secrets.xcconfig`, `Utilities/SupabaseConfig.swift`, `Utilities/TelegramFeedbackConfig.swift` |
| **Supabase Edge Functions** | `supabase/functions/register-device/index.ts`, `ai-assist/index.ts`, `support-chat/index.ts`, `submit-feedback/index.ts`, `admin-api/index.ts`, `support-admin/index.ts`, `admin-ops/index.ts`, `delete-account/index.ts` |
| Supabase migrations | `supabase/migrations/*.sql` (5 files — feedback rate limit, devices/admins/announcements, RPC lock-down, live counts, support chat identity) |
| Build manifest | `project.yml` (XcodeGen — edit this, never the `.xcodeproj` directly) |
| Unit tests | `HoursTrackerTests/*.swift` (484 tests — one file roughly per Manager/Model) |
| UI tests | `HoursTrackerUITests/*.swift` (`ScreenshotTests`, `DesignQATests`, `MarketingShotsTests`, `SettingsQATests`, `OnboardingRTLUITests`, `HomeGreetingLayoutUITests`, `DaySummarySwipeUITests`) |

---

## Section 4: Known Bugs & Fixes History

Document these so a future agent doesn't reintroduce the same bug class.

### 4.1 Settings "jump" / ghost-gap pop-in
- **Symptom**: rows that depend on an async-resolved condition (e.g. `if viewModel.isAdmin`) visibly popped in after the page had already rendered, on both the Form and an earlier ScrollView+card redesign.
- **Root cause**: `Form`/`List` apply an implicit insertion-diffing animation on first render of a pushed screen; a card/opacity-toggle approach tried as a different fix instead left permanent ghost gaps/dangling dividers for rows whose condition was false (Form row chrome reserves space even for `.opacity(0)` content).
- **Fix**: `.transaction { $0.disablesAnimations = true }` applied to every page built by the shared `settingsPage()` helper, plus `WorkRulesView` and `RemindersView` (which build their own `Form`). `isAdmin` itself is resolved once at `AppViewModel.init()`, long before Settings can open, so this is defense-in-depth, not the only mitigation.
- **Don't**: reach for `.redacted(reason: .placeholder)` on a boolean that's permanently false for most users — tried for `isAdmin`, produces a permanently-stuck shimmering section. Reserve `.redacted` for genuinely transient async values.

### 4.2 Export tab freeze ("Gesture: System gesture gate timed out")
- **Symptom**: rapidly dragging the date pickers/quick pills in the Export tab froze the UI; iOS logged a gesture-gate timeout.
- **Root cause**: `updatePreview()` called `OvertimeCalculator.aggregate(...)` synchronously on the main thread, triggered on every `.onChange` of range/filter state — rapid dragging fired this repeatedly, starving the gesture recognizer.
- **Fix**: moved the aggregate call to `Task.detached(priority: .userInitiated)`; the previous in-flight task is cancelled before a new one starts, and the result checks `Task.isCancelled` before writing back via `MainActor.run`, so a stale result for an already-superseded filter can never overwrite a newer one.
- **Verified**: a 16-tap rapid-fire XCUITest across all 4 quick pills, immediately followed by a tab switch, confirmed no freeze.

### 4.3 Legal consent screen — blue tint on "Terms of Use"/"Privacy Policy"
- **Symptom**: the two link rows rendered in a cyan/blue tint instead of the `.primary` (white) color their `Text` explicitly requested.
- **Root cause**: a bare `NavigationLink` outside a `List` applies its own default button styling to its entire label, overriding an inner `.foregroundStyle(.primary)`.
- **Fix**: `.buttonStyle(.plain)` added to both `NavigationLink`s in `LegalConsentView.swift`.
- **Verified**: pixel-sampled the rendered screenshot before/after — RGB went from ≈(4, 195, 218) to ≈(217, 217, 217), i.e. actually neutral now, not just visually close.

### 4.4 Backend security audit (2026-11-08)
- **`ai-assist` — critical**: accepted any 16–64 char string as `deviceId` with no IP rate limit, letting anyone with the public anon key mint unlimited fake device identities, bypass the per-device quota (3/day, 10/week), and exhaust the shared `AI_GLOBAL_DAILY_CAP`. Fixed: require `deviceId` to be a real UUID; added a 20/hour per-IP `check_rate_limit` call before the quota check.
- **`support-chat`**: `list`/`status` actions had zero rate limit (only `send` did). Fixed: added a 60/hour per-device rate limit; tightened `deviceId` to require UUID format.
- **`submit-feedback`**: no length caps on text/caption/filename/attachment, and `documentName`/`caption` were spliced unescaped into a hand-built multipart body — a crafted filename containing a quote or CRLF could forge extra form fields (e.g. `chat_id`) in the Telegram request. Fixed: added length caps; strip CR/LF and escape `"` before building the body.
- **Code drift**: `ai-assist` and `admin-ops` existed live on Supabase but were never committed. Added both under `supabase/functions/`.
- **Confirmed already-correct** (no change needed): `admin-api`/`support-admin`/`admin-ops` all verify the session JWT then check `public.admins`; `delete-account`/`register-device` take identity only from the verified token; `profiles`/`user_backups` RLS policies correctly scope to `auth.uid()`.
- All three fixes deployed to production and smoke-tested live (malformed input now rejected before touching quota/Gemini/Telegram).

### 4.5 Watch target's Localizable.xcstrings silently drifted (missing Thai)
- **Symptom**: discovered while auditing localization completeness — 1195 of 1213 keys in `HoursTrackerWatch/Resources/Localizable.xcstrings` had no Thai translation, while every other language was complete.
- **Root cause**: that path is supposed to be a symlink to the main app's catalog (added in an earlier fix for a *different* bug — Xcode's String Catalog compiler silently compiles an empty catalog for a target referencing a file outside its own directory). Xcode's String Catalog editor had materialized the symlink into an independent 42,000-line file at some point; it then drifted out of sync starting right around when Thai was added to the main catalog.
- **Fix**: confirmed zero unique content and zero text divergence on every shared key between the two files, then **restored the symlink** rather than hand-copying 1195 strings — this is the structurally correct fix (makes this exact drift impossible again, rather than a one-time patch).
- **Rule going forward**: see §0/§2, rule 7.

### 4.6 Hardcoded Hebrew literals shipping to all languages (2026-11-08)
- **Symptom**: two `Text(...)` calls had literal Hebrew strings instead of `L10n` lookups, so English/Arabic/Russian/Thai users saw Hebrew text.
  - `SettingsView.swift`'s Work & Pay group footer ("These settings apply to your current workplace...").
  - `HistoryView.swift`'s holiday banner ("Holiday {name}") — also always used `holiday.hebrewName`, never `englishName`, regardless of app language.
- **Fix**: added `settings.workGroupFooter` and `history.holidayBanner %@` to `Localizable.xcstrings` (all 5 languages), added `L10n.settingsWorkGroupFooter` and `L10n.historyHolidayBanner(_:)` accessors, replaced both literals. The holiday banner now also picks `holiday.hebrewName` vs. `holiday.englishName` based on `AppLocale.current`, matching the existing fallback pattern used elsewhere for holiday names (there's no Arabic/Russian/Thai holiday name field on `ResolvedHoliday`).

---

## Section 5: Supabase Backend Rules

Apply these to every Edge Function, new or existing:

1. **Never trust a client-supplied identifier as if it were authenticated.** Any per-install `deviceId` must be validated as a real UUID (`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`) *and* rate-limited by IP (`req.headers.get("x-forwarded-for")`), not just by the claimed id.
2. **Every action needs a rate limit, reads included, not just writes.** Reuse the generic `check_rate_limit(bucket, key, limit, window_minutes)` RPC (`supabase/migrations/20260927100000_admin_devices_announcements.sql`) — don't invent a new mechanism per function.
3. **Admin/owner endpoints verify `auth.getUser(token)` then check `public.admins` on every single call.** The client's own `isAdmin` flag only decides whether a UI entry point is shown — it grants no access.
4. **Never splice a client-supplied string into a raw hand-built request body** (multipart or otherwise) without stripping CR/LF and escaping your delimiter character.
5. **Cap every input's length server-side**, even if the app already limits it client-side — these endpoints are reachable directly by anyone holding the public anon/publishable key, by design (that's what "publishable" means here — see `SupabaseConfig.swift`'s doc comment).
6. **Identity (user id, email) always comes from the verified session token** (`supabase.auth.getUser(token)`), never from the request body.
7. **A table only the service role touches should have RLS enabled with *zero* policies.** That's correct, not a misconfiguration — `anon`/`authenticated` get zero access, and authorization lives entirely in the function code per the rules above. Tables the app's Swift client touches *directly* with the user's own session (`user_backups`, `profiles`) need real `auth.uid() = ...` policies instead.
8. **Commit the source of every deployed function** under `supabase/functions/<name>/index.ts` — `ai-assist` and `admin-ops` existed live without a committed source for a while; don't let that happen again.
9. Supabase's "Leaked Password Protection" (Authentication → Policies) is currently **off** project-wide — recommended but not yet enabled; it's a dashboard setting, not code.

---

## Section 6: File Structure Overview

```
HoursTracker-clean/
├── AI_AGENT_BRIEF.md              ← older project brief (superseded in scope by this file; still has narrative detail)
├── MASTER_MAP.md                  ← this file
├── project.yml                    ← XcodeGen manifest — edit this, run `xcodegen generate`
├── HoursTracker.xcodeproj/        ← GENERATED, do not hand-edit
├── HoursTracker/                  ← main iOS app target
│   ├── HoursTrackerApp.swift      ← @main, 5-tab MainTabView, deep-link routing
│   ├── AppDelegate.swift          ← UIKit lifecycle, quick actions, DEBUG-only UITEST_* hooks
│   ├── ViewModels/                ← AppViewModel + extensions, AppLockController, Assistant/Payslip VMs
│   ├── Views/                     ← every SwiftUI screen (58 files) — Home/History/Payslips/Export/Settings and their sub-screens
│   ├── Models/                    ← WorkSession, WorkplaceSettings, OvertimeCalculator, IsraeliTaxEstimator, …
│   ├── Managers/                  ← singleton managers, one concern each
│   │   ├── Assistant/             ← AssistantEngine, LLM router, BYOK + managed providers
│   │   └── Scanner/                ← Vision/PDFKit OCR pipeline, LLM-assist providers
│   ├── Intents/                   ← Siri/Shortcuts App Intents
│   ├── Shared/                    ← compiled into MULTIPLE targets (LivePayCurve → app+widget, WatchSnapshot → app+Watch)
│   ├── Utilities/                 ← L10n, AppLocale, theme system, KeychainStore, SupabaseConfig, …
│   ├── Config/                    ← LocalSecrets.swift (empty placeholders), Secrets.xcconfig
│   └── Resources/
│       └── Localizable.xcstrings  ← SINGLE SOURCE OF TRUTH for all 5 languages
├── HoursTrackerWidget/            ← widget extension target (WidgetKit + ActivityKit + App Intents)
├── HoursTrackerWatch/             ← watchOS companion app target
│   └── Resources/
│       └── Localizable.xcstrings  ← SYMLINK → ../../HoursTracker/Resources/Localizable.xcstrings (§0 rule 7)
├── HoursTrackerTests/             ← unit tests (484 tests)
├── HoursTrackerUITests/           ← XCUITests incl. screenshot/QA automation
├── supabase/
│   ├── functions/                 ← 8 Edge Functions (Deno) — register-device, ai-assist, support-chat,
│   │                                 submit-feedback, admin-api, support-admin, admin-ops, delete-account
│   ├── migrations/                ← 5 SQL migrations (rate limits, devices/admins/announcements, support chat)
│   └── config.toml
├── docs/                          ← architecture/privacy/release-process docs (tracked, not cleanup targets)
├── marketing/                     ← App Store screenshots/assets (tracked)
└── design-qa/                     ← past manual/automated QA screenshot evidence (untracked, not build output — leave alone)
```

---

## Section 7: Agent Change Protocol

Follow this order for every change, no matter which AI wrote the code:

1. **Locate the file(s).** Use Section 3's routing table first; fall back to `grep -rn "<symbol>"` across `HoursTracker*/` only if the table doesn't cover it.
2. **Check Section 0/2 for a rule that applies.** If the change touches text, color, pay math, navigation, Settings layout, live pay, Watch localization, or a Supabase function, read that rule's "why" before editing — it tells you the failure mode to avoid, not just the mechanical rule.
3. **Check Section 4 for prior art.** If the change is anywhere near Settings animation, Export performance, Legal consent styling, Live Activity/widget pay numbers, or the Watch string catalog, confirm you're not re-introducing a documented, already-fixed bug.
4. **Edit only the right layer.** Don't add a new abstraction, helper type, or "just in case" parameter beyond what the change needs — match the existing pattern in the file you're editing.
5. **If you added/removed/renamed a file**, run `xcodegen generate` before building.
6. **Build**: `xcodebuild -project HoursTracker.xcodeproj -scheme HoursTracker -destination 'platform=iOS Simulator,name=<device>' build`.
7. **Run the full unit test suite**: `-only-testing:HoursTrackerTests test`, confirm `Executed 484 tests, with 0 failures` (or the current total, if tests were added/removed as part of the change).
8. **If the change is UI-visible**, verify on the simulator — a temporary XCUITest + screenshot if no existing test covers the screen, deleted afterward if genuinely temporary.
9. **Report plainly**: "Success" with what was verified, or "Build Error" with the actual compiler/test output — never a guess, never "should work now" without having actually run the build/tests.
10. **If something doesn't fit** — a rule conflicts with the requested change, or the requested change would reintroduce a Section 4 bug — say so explicitly instead of silently picking a side.
