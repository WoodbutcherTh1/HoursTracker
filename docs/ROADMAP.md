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

> **Status:** implemented — unpaid breaks (per-session, with an auto-applied default for 6h+ shifts), rest-day/holiday rates (150%/175%/200%, auto-tagged from the configured weekly rest day), night shifts (7h standard day, auto-detected at ≥ 2h between 22:00–06:00), multiple sessions per day now share one daily overtime/gas allowance, and pay display uses a configurable currency. Separately delivered by the payroll/OCR branch: net-pay estimation with credit points and custom payroll months. **Weekly overtime cap** now implemented: `weeklyStandardHours` (default 42h) and `weeklyOvertimeCapHours` (default 12h) in `WorkplaceSettings`; `aggregate()` promotes daily-100% hours above the weekly threshold to 125%/150% tiers. **Home-screen widget** now shows live pay estimates using the same daily OT split logic. **Bundled holiday calendar** now implemented: `IsraeliHolidayCalendar` computes the main statutory rest days (Rosh Hashanah, Yom Kippur, Sukkot I, Shemini Atzeret, Pesach I/II/VII/VIII, Shavuot) from the Hebrew calendar and auto-tags them as holidays. **Sick-day annual cap** now enforced: 18 days/year (`AppViewModel.sickDaysPerYearCap`), matching the 1.5 days/month accrual practice. Still open: rest-day auto-tagging that accounts for the worker's religion-specific rest day beyond a single weekday setting.

- **Break/rest deduction** — support an unpaid break duration per session (or per settings default) subtracted before the overtime split.
- **Weekly overtime and rest-day rates** — work on the weekly rest day (Shabbat/Friday depending on the worker) pays 150% from the first hour, with its own overtime tiers. Requires tagging sessions or settings with the worker's rest day.
- **Holiday rates** — Israeli public holidays pay like rest days; a bundled holiday calendar (or manual "holiday" flag per session) would cover it.
- **Night-shift standard day** — a night shift's standard day is shorter (7h under the Hours of Work and Rest Law); detect or let the user flag night shifts.
- **Multiple sessions per day** — the one-session-per-day rule (enforced in `AppViewModel.clockIn` and `addManualSession`) prevents split shifts. Relaxing it means deciding how the daily overtime split applies across the day's combined hours (the calculator already works on total daily hours, so aggregation per day is the natural approach).
- **Configurable currency/locale** — `DayPayBreakdown.formattedTotalPay` hardcodes `₪`; move to `NumberFormatter` currency style driven by a settings field. Same for the default workplace name (`"Kahana"` in `WorkplaceSettings.default`), which should be empty out of the box.

## Phase 3 — UX & platform features

> **Status (mostly done):** permission handling landed ahead of schedule — Always-location and notifications are now requested only when the user opts into arrival reminders in Settings, replacing the launch-time request this phase originally called out. **Geofence exit detection** now implemented: exiting the workplace region while a session is open sends a "leaving work? clock out!" notification. **Live Activity / Dynamic Island** and **home-screen widget** now implemented: the Lock Screen banner and Dynamic Island show a live elapsed-time + estimated-pay counter while a shift is running; the home-screen widget shows today's hours and earnings (small, medium and large sizes). Widgets are now **interactive** (Clock In / Clock Out AppIntent buttons), deep-link into the right tab, respect a **hide-pay privacy toggle**, and work in StandBy (iOS 17) as-is. **Monthly summary view** now shipped: History shows a six-month hours bar chart plus average monthly pay (Swift Charts). **Onboarding flow** now shipped: a three-page first-launch explainer presented once (AppLock/location copy is opt-in as before). Still open: multiple workplaces.

- ~~Live Activity / Dynamic Island~~ — done. Lock Screen banner + Dynamic Island show elapsed time + estimated pay during an active shift (masked when the hide-pay toggle is on).
- ~~Home-screen widget~~ — done. Small / medium / large widgets show today's and this week's hours and earnings, with status indicators (Working / Done / Off) and Clock In / Clock Out buttons (iOS 17 AppIntents).
- ~~Monthly summary view~~ — done. Six-month hours chart + average monthly pay in History.
- **Multiple workplaces** — settings, rates, and geofences are singletons today (`WorkplaceSettings`, one `workplace-geofence` region). Support a workplace list, each with its own rates and geofence, and tag sessions with a workplace.
- ~~Onboarding flow~~ — done. Three-page first-launch explainer (one-tap tracking, Israeli pay rules, privacy-first) presented once via `MainTabView`.
- ~~Geofence exit detection~~ — done. `didExitRegion` sends a "leaving work?" notification when a session is open.
- ~~Quick actions + deep links~~ — done. Long-press the app icon to clock in/out, add hours, or scan; widget areas deep-link to the correct tab (`hourstracker://`).

## Phase 4 — Distribution & polish

> **Status (mostly done):** app icon, privacy manifest (`PrivacyInfo.xcprivacy`), in-app privacy policy, delete-all-data action, localized Info.plist strings, encryption-exemption flag, and reviewer-friendly permission copy have all landed. Remaining below.

- ~~App icon and branding~~ — done.
- **Accessibility pass** — Dynamic Type audit on the custom-drawn views, VoiceOver labels on the timer and clock buttons; RTL is already exercised via ar/he.
- **Unify localization** — now three mechanisms: the String Catalog, `AppLocale`'s hardcoded notification strings, and `ExportCopy`'s per-language report table. Each exists for a reason (background language selection; report language independent of UI locale), but string changes touch up to three places — consolidate behind one lookup that takes an explicit locale.
- **Data export/import safety** — a full JSON backup/restore (the persistence format is already JSON) protects users who lose the device, especially now that cloud sync is off by default.
- **TestFlight / App Store submission** — screenshots in all three languages, App Store metadata, review notes for the opt-in Always-location usage.
- **Cloud sync (parked)** — CloudKit is compiled out behind `HTCloudKitEnabled` because personal-team provisioning cannot carry iCloud entitlements. Revisit (with `CKSyncEngine`) once a paid Apple Developer team is available — see `docs/CKSYNCENGINE.md` for the feasibility assessment (deferred: push delivery needs the paid entitlements).

## Suggested sequencing

| Milestone | Contents | Outcome |
|---|---|---|
| 0.2 | Phase 1 complete | Trustworthy storage/sync, CI, real test suite |
| 0.3 | Breaks, rest-day/holiday rates, currency setting | Legally accurate pay for common cases |
| 0.4 | Live Activity, widget, monthly summaries, onboarding, quick actions | Daily-driver UX |
| 0.5 | Multiple workplaces | General-audience ready |
| 1.0 | Phase 4 complete | App Store release |
