# HoursTracker — Development Roadmap

This roadmap is grounded in the current state of the code (see `docs/ARCHITECTURE.md`). Phases are ordered by risk: first make what exists trustworthy, then deepen the pay engine, then grow the product surface.

## Phase 1 — Hardening & correctness

The app's job is to be a trustworthy record of hours and pay, so silent data loss is the first thing to eliminate.

> **Status:** implemented, except the CKSyncEngine migration which remains open. Save failures now surface as an alert and CloudKit failures are logged; cloud writes are incremental; a session left open past midnight stays active and blocks a second clock-in; unit tests cover merge, export filtering, clock-out estimation, and view-model flows; CI runs the test suite on every push and pull request.

- **Surface persistence and sync errors.**
  `PersistenceManager` swallows every load/save error with `try?`, and `CloudKitSyncManager` catches upload/delete failures with empty `catch` blocks. A failed save currently looks identical to a successful one. Introduce an error channel (e.g. a `@Published` alert state on `AppViewModel`) and at minimum log failures; `SyncState.failed` already exists and is only partially used.
- **Make cloud writes incremental.**
  `SyncingPersistenceStore.saveSessions(_:)` re-uploads *every* session on *every* mutation — one clock-out triggers N CloudKit saves. Track dirty records (the `modifiedAt` field already exists) and upload only what changed. Evaluate migrating to `CKSyncEngine` (iOS 17+), which would also replace the hand-rolled last-write-wins merge and give push-based sync instead of foreground-only polling.
- **Guard the open-session edge cases.**
  A session left open across midnight breaks the "one session per day" invariants: `activeSession` only looks at *today's* day, so yesterday's open session becomes unreachable from the Home tab and can never be clocked out except via History editing. Define the behavior (auto-close at midnight, or find the newest open session regardless of day) and test it.
- **Expand unit tests beyond the calculator.**
  The protocols (`PersistableStore`, `CloudSyncing`, `LocationReminderManaging`) make this cheap. Priority targets: `CloudKitSyncManager.mergeSessions` (conflict resolution), `ExportManager.filter` (month/custom-range boundaries), `LocationReminderManager.estimatedClockOutTime` (averaging + rounding), and `AppViewModel` clock-in/out flows with an in-memory store.
- **Add CI.**
  A GitHub Actions workflow that runs `xcodegen generate` and `xcodebuild test` on every push. Nothing enforces green tests today.
- **Fix the export date-range filter for custom ranges.**
  `ExportDateRange.custom` compares against `session.date` (start of day) with an end bound of `endOfDay - 1s`; verify inclusive/exclusive behavior around DST transitions and add tests.

## Phase 2 — Pay-engine depth (Israeli labor law)

The calculator handles the daily 100/125/150 split; Israeli law has more dimensions that a worker relying on this app will eventually hit.

> **Status:** implemented — unpaid breaks (per-session, with an auto-applied default for 6h+ shifts), rest-day/holiday rates (150%/175%/200%, auto-tagged from the configured weekly rest day), night shifts (7h standard day, auto-detected at ≥ 2h between 22:00–06:00), multiple sessions per day now share one daily overtime/gas allowance, and pay display uses a configurable currency. Separately delivered by the payroll/OCR branch: net-pay estimation with credit points and custom payroll months. Still open: weekly overtime caps, a bundled holiday calendar (holidays are a manual per-session flag today), and rest-day auto-tagging that accounts for the worker's religion-specific rest day beyond a single weekday setting.

- **Break/rest deduction** — support an unpaid break duration per session (or per settings default) subtracted before the overtime split.
- **Weekly overtime and rest-day rates** — work on the weekly rest day (Shabbat/Friday depending on the worker) pays 150% from the first hour, with its own overtime tiers. Requires tagging sessions or settings with the worker's rest day.
- **Holiday rates** — Israeli public holidays pay like rest days; a bundled holiday calendar (or manual "holiday" flag per session) would cover it.
- **Night-shift standard day** — a night shift's standard day is shorter (7h under the Hours of Work and Rest Law); detect or let the user flag night shifts.
- **Multiple sessions per day** — the one-session-per-day rule (enforced in `AppViewModel.clockIn` and `addManualSession`) prevents split shifts. Relaxing it means deciding how the daily overtime split applies across the day's combined hours (the calculator already works on total daily hours, so aggregation per day is the natural approach).
- **Configurable currency/locale** — `DayPayBreakdown.formattedTotalPay` hardcodes `₪`; move to `NumberFormatter` currency style driven by a settings field. Same for the default workplace name (`"Kahana"` in `WorkplaceSettings.default`), which should be empty out of the box.

## Phase 3 — UX & platform features

> **Status (partial):** permission handling landed ahead of schedule — Always-location and notifications are now requested only when the user opts into arrival reminders in Settings, replacing the launch-time request this phase originally called out. A full onboarding flow is still open.

- **Live Activity / Dynamic Island** for the running session — the live timer currently exists only inside the app; a Live Activity makes clock-out one glance away and reduces forgotten sessions (which the 23:00 alert only patches).
- **Home-screen widget** showing today's status and the week's hours.
- **Monthly summary view** — History is a flat list; add per-month totals (hours, overtime split, pay) with simple charts (Swift Charts) so exports aren't the only way to see aggregates.
- **Multiple workplaces** — settings, rates, and geofences are singletons today (`WorkplaceSettings`, one `workplace-geofence` region). Support a workplace list, each with its own rates and geofence, and tag sessions with a workplace.
- **Onboarding flow** — permissions (Always-location, notifications) are requested at first launch from `AppViewModel.init` with no explanation; a short onboarding explaining why, plus guided workplace/rate setup, will improve grant rates.
- **Geofence exit detection** — the region only fires on entry (`notifyOnExit = false`); an exit event while clocked in could prompt "leaving work — clock out?", which is more accurate than the averaged-time reminder.

## Phase 4 — Distribution & polish

> **Status (mostly done):** app icon, privacy manifest (`PrivacyInfo.xcprivacy`), in-app privacy policy, delete-all-data action, localized Info.plist strings, encryption-exemption flag, and reviewer-friendly permission copy have all landed. Remaining below.

- ~~App icon and branding~~ — done.
- **Accessibility pass** — Dynamic Type audit on the custom-drawn views, VoiceOver labels on the timer and clock buttons; RTL is already exercised via ar/he.
- **Unify localization** — now three mechanisms: the String Catalog, `AppLocale`'s hardcoded notification strings, and `ExportCopy`'s per-language report table. Each exists for a reason (background language selection; report language independent of UI locale), but string changes touch up to three places — consolidate behind one lookup that takes an explicit locale.
- **Data export/import safety** — a full JSON backup/restore (the persistence format is already JSON) protects users who lose the device, especially now that cloud sync is off by default.
- **TestFlight / App Store submission** — screenshots in all three languages, App Store metadata, review notes for the opt-in Always-location usage.
- **Cloud sync (parked)** — CloudKit is compiled out behind `HTCloudKitEnabled` because personal-team provisioning cannot carry iCloud entitlements. Revisit (with `CKSyncEngine`) once a paid Apple Developer team is available.

## Phase 5 — Assistant & natural-language retrieval

> **Status:** implemented (v1.3). A chat assistant answers questions about the user's own hours, pay, days off, and payslips, and can generate a report, in ar/he/en. Architecture: the LLM only classifies the question into a structured `AssistantPlan` (tool + filters); `AssistantEngine` computes every figure on-device from the user's real data via `OvertimeCalculator` / `PayslipStore` / `ExportManager`, so the model cannot invent a number and its prose never reaches the screen. Reuses the Smart Scanner cloud toggle + API key; no on-device fallback (reports itself unavailable when cloud is off). See `docs/ARCHITECTURE.md` → **AI Assistant**.

Still open:

- **Broaden the opt-in label.** One toggle ("Smart Scanner cloud extraction") now gates both the scanner and the assistant. Rename it to something like "Cloud AI features" so the consent text matches what it controls, and update `docs/PRIVACY.md` / the App Store questionnaire together.
- **Assistant App Privacy review.** The question field is free text; confirm whether `NSPrivacyCollectedDataTypeOtherUserContent` should be declared alongside `OtherFinancialInfo` before the next submission (`docs/PRIVACY_MANIFEST.md` tracks this).
- **More tools.** Trends over time, comparisons between periods, and "what changed vs last month" are natural next actions for the same plan/engine split.

## Suggested sequencing

| Milestone | Contents | Outcome |
|---|---|---|
| 0.2 | Phase 1 complete | Trustworthy storage/sync, CI, real test suite |
| 0.3 | Breaks, rest-day/holiday rates, currency setting | Legally accurate pay for common cases |
| 0.4 | Live Activity, widget, monthly summaries | Daily-driver UX |
| 0.5 | Multiple workplaces, onboarding | General-audience ready |
| 1.0 | Phase 4 complete | App Store release |
| 1.3 | Phase 5 — assistant & payslip library | Natural-language access to own data |
