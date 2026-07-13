# HoursTracker — Development Roadmap

This roadmap is grounded in the current state of the code (see `docs/ARCHITECTURE.md`). Phases are ordered by risk: first make what exists trustworthy, then deepen the pay engine, then grow the product surface.

## Phase 1 — Hardening & correctness

The app's job is to be a trustworthy record of hours and pay, so silent data loss is the first thing to eliminate.

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

- **Break/rest deduction** — support an unpaid break duration per session (or per settings default) subtracted before the overtime split.
- **Weekly overtime and rest-day rates** — work on the weekly rest day (Shabbat/Friday depending on the worker) pays 150% from the first hour, with its own overtime tiers. Requires tagging sessions or settings with the worker's rest day.
- **Holiday rates** — Israeli public holidays pay like rest days; a bundled holiday calendar (or manual "holiday" flag per session) would cover it.
- **Night-shift standard day** — a night shift's standard day is shorter (7h under the Hours of Work and Rest Law); detect or let the user flag night shifts.
- **Multiple sessions per day** — the one-session-per-day rule (enforced in `AppViewModel.clockIn` and `addManualSession`) prevents split shifts. Relaxing it means deciding how the daily overtime split applies across the day's combined hours (the calculator already works on total daily hours, so aggregation per day is the natural approach).
- **Configurable currency/locale** — `DayPayBreakdown.formattedTotalPay` hardcodes `₪`; move to `NumberFormatter` currency style driven by a settings field. Same for the default workplace name (`"Kahana"` in `WorkplaceSettings.default`), which should be empty out of the box.

## Phase 3 — UX & platform features

- **Live Activity / Dynamic Island** for the running session — the live timer currently exists only inside the app; a Live Activity makes clock-out one glance away and reduces forgotten sessions (which the 23:00 alert only patches).
- **Home-screen widget** showing today's status and the week's hours.
- **Monthly summary view** — History is a flat list; add per-month totals (hours, overtime split, pay) with simple charts (Swift Charts) so exports aren't the only way to see aggregates.
- **Multiple workplaces** — settings, rates, and geofences are singletons today (`WorkplaceSettings`, one `workplace-geofence` region). Support a workplace list, each with its own rates and geofence, and tag sessions with a workplace.
- **Onboarding flow** — permissions (Always-location, notifications) are requested at first launch from `AppViewModel.init` with no explanation; a short onboarding explaining why, plus guided workplace/rate setup, will improve grant rates.
- **Geofence exit detection** — the region only fires on entry (`notifyOnExit = false`); an exit event while clocked in could prompt "leaving work — clock out?", which is more accurate than the averaged-time reminder.

## Phase 4 — Distribution & polish

- **App icon and branding** — no icon assets exist yet.
- **Accessibility pass** — Dynamic Type audit on the custom-drawn views, VoiceOver labels on the timer and clock buttons; RTL is already exercised via ar/he.
- **Unify localization** — `AppLocale`'s hardcoded notification strings duplicate the localization mechanism; fold them into the String Catalog and drop the manual language switch.
- **Data export/import safety** — a full JSON backup/restore (the persistence format is already JSON) protects users who lose iCloud access.
- **TestFlight / App Store preparation** — privacy manifest, App Store location-usage review notes (Always authorization needs strong justification), screenshots in all three languages.

## Suggested sequencing

| Milestone | Contents | Outcome |
|---|---|---|
| 0.2 | Phase 1 complete | Trustworthy storage/sync, CI, real test suite |
| 0.3 | Breaks, rest-day/holiday rates, currency setting | Legally accurate pay for common cases |
| 0.4 | Live Activity, widget, monthly summaries | Daily-driver UX |
| 0.5 | Multiple workplaces, onboarding | General-audience ready |
| 1.0 | Phase 4 complete | App Store release |
