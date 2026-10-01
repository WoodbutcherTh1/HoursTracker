# HoursTracker — Work Plan (2026-09)

Agreed with the owner in a planning session. Each item lands as its own commit
on `claude/planning-requests-bb6hz1`. Status: ⬜ todo · 🟡 in progress · ✅ done.

## Phase 1 — Recover lost work (branches never merged into `main`)

| # | Item | Source branch | Status |
|---|------|---------------|--------|
| B2 | Prevent cloud sync from silently erasing data | `claude/jolly-wright-6ep32d` | ✅ |
| B1 | Forgot-password flow (code-based reset) | `claude/jolly-wright-6ep32d` | ✅ |
| B3 | Widget interactivity, Watch hours display, Live Activity staleness | `claude/jolly-wright-6ep32d` | ✅ |
| B4 | Watch app showing raw localization keys | `claude/jolly-wright-6ep32d` | ✅ |
| B5 | Neon hourglass app icon (iPhone + Watch) | `claude/jolly-wright-6ep32d` / `claude/neon-app-icon` | ✅ |
| B12 | Assistant: honour cloud opt-out, visibility toggle | `assistant-review-fixes` | ✅ |
| B13 | Timeout on CloudKit sync so a hang surfaces as failed | `claude/agitated-mestorf-e371c0` | ✅ |
| B14 | In-app language override actually changes language | `claude/fix-in-app-language-resolution` | ✅ already fixed on `main` (lproj-first lookup) |

## Phase 2 — Break button ("יצאתי להפסקה") — C1 ✅ (awaiting CI + device test)

- Session records break intervals (start/end); `breakMinutes` derived from them;
  old sessions keep decoding.
- Settings: target break length (default 30 min). A recorded break suppresses
  the automatic `defaultBreakMinutes` deduction.
- Home: "Start break" next to the door while clocked in; countdown
  ("12 of 30 min left"); "Back to work".
- Local notifications: a heads-up a few minutes before the break ends
  (lead time configurable: 2 / 5 / 10 min, default 5) and "break is over" when the target length is reached.
  Both cancelled when the user taps "Back to work" early.
- Fully synced: app, Watch, widgets, Live Activity / Dynamic Island — break
  can be started/ended from any of them.
- Workplace setting **Breaks are paid** (default off). Off: break stops the paid
  clock and is deducted. On: break is a reminder only — pay keeps counting and
  the automatic default break is never applied.

### Notifications settings screen (shared by Phases 2, 5, 6)

- A dedicated **Notifications** section in Settings where the user turns each
  notification type on/off individually:
  - Break: "ending soon" reminder (+ lead time) and "break over"
  - Shift: clock-in reminder / clock-out reminder (Phase 5)
  - Location: arrival / left-work reminders (existing geofence feature, moved here)
  - Announcements from the app owner (Phase 6 push broadcasts)
- Shows a banner with a shortcut to iOS Settings when notification permission is denied.

## Full control from widgets / Lock Screen — C6 ✅ (awaiting CI + device test)

- Widget and Live Activity buttons (clock in/out, start/end break) are
  `LiveActivityIntent`s shared with the app, so iOS runs them in the app's
  process (background launch if needed) — the action applies immediately and
  the widget refreshes, without opening the app.
- Lock Screen banner + expanded Dynamic Island get Break/Back + Clock Out buttons.
- If the phone is locked and the app's data is still protected, the tap is
  kept (with its time) and applied at unlock.

## Phase 3 — Live hours/money counter everywhere — C3 ✅ (awaiting CI + device test)

- One source: the phone builds a `LivePayCurve` (cumulative gross/net vs. paid
  seconds, 5-min samples, 16 h ahead) with the real pay engine; Home, Watch,
  widgets and Live Activity all read it, so they show the same figure.

- App, Watch, widgets and Dynamic Island all derive from the same clock-in
  time so the numbers match.
- Hours tick every second everywhere (system timer text in widgets / Live
  Activity). Money ticks every second in app + Watch; in widgets / Live
  Activity it refreshes as often as the system allows (Apple does not allow
  per-second computation there).

## Phase 4 — History swipe behaviour — C4 ✅ (awaiting CI + device test)

- Swipe on the week strip / arrows row → move one **week**.
- Swipe inside the full-history (expanded) grid → move one **month** (payroll period).
- The period title header stays pinned and never disappears during the
  transition (bug seen moving 9 → 8).

## Phase 5 — Shift reminders by usual schedule — C2 ✅ (awaiting CI + device test)

- Clock In / Clock Out buttons right on the reminder (no need to open the app).

- Learn usual clock-in / clock-out time **per weekday** from past sessions.
- Notify **5 min before** the usual start ("don't forget to clock in") and
  5 min before the usual end ("don't forget to clock out").
- Cancelled automatically when already clocked in / out. No location needed;
  skip rest days; on/off toggle in Settings. Existing geofence reminders stay.

## Phase 5.5 — Data safety ✅ (awaiting CI + device test)

- Undo banner after deleting a shift; "Recently deleted" bin (30 days) with restore.
- Daily automatic on-device backup (14 days) + restore screen (pre-restore snapshot first).
- Account backup refreshed automatically after changes (only additive — never
  overwrites an account copy that has shifts this device lacks).
- Delete-all wipes the bin and backups too.

## Phase 6 — Owner/Admin dashboard — C5 🟡 code done; needs owner setup (`docs/ADMIN_SETUP.md`) + CI + device test

- Server-side roles in Supabase (owner = the account email); RLS + Edge
  Functions reject non-admins. Never trust a client-side email check alone.
- Hidden "Admin" section in Settings, visible only to admins.
- Broadcast messages: three language fields (he / ar / en) with an
  "auto-translate" helper the admin reviews before sending. Each user receives
  the message **in their in-app language**.
- Targeting: all users, by language, by app version, or selected users.
- Delivery: APNs push (Auth Key `.p8` stored as a Supabase secret — never in
  the repo) + in-app banner shown once.
- Device registration: push token, app language, app version (updated on change).
- Stats: aggregate only (user counts, active users, version distribution,
  Watch/widget adoption). No per-user wage/shift data.

## Phase 7 — Remaining recovered work 🟡 (awaiting CI + device test; 3 items need the owner's choice)

| # | Item | Source | Status |
|---|------|--------|--------|
| — | Widget + Live Activity text in he/ar/en, follows the in-app language, RTL | `chat-session` 39fcaac / 8a62f93 | ✅ |
| B6 | 6-month hours/pay trend chart | `install-claude-code-tool` | ✅ already on `main` (History `MonthlyTrendCard`) |
| B7 | Payslips as its own tab | `install-claude-code-tool` d1afafc | ✅ |
| B8 | Lock Screen widget (rectangular / circular / inline, read-only) | `chat-session` / `install-claude-code-tool` | ✅ |
| B9 | History header tap toggles (date, net/gross) | `chat-session` / `project-thread` | ✅ already on `main` |
| B10 | CSV-column-aware timesheet importer | `chat-session` 223ca96 | ✅ |
| B11 | Icon-led Settings section headers | `project-thread` cd28a75 | ✅ |
| B15 | Full backup/restore + rolling auto backups | `cursor/full-backup-restore*` | ✅ superseded (full export/import on `main` + Phase 5.5) |
| B16 | Monthly payroll-period overview ring in History | `cursor/history-monthly-overview` | ❓ owner's choice (adds a large card above the list) |
| B17 | Older Cursor fixes | `cursor/*` | ✅ addRow bound, dotted-date scanner parsing, Settings tab jump, sparkline open-day, sync overwrite race, history default period (already), scanner→form (already). ⏭ rollback-on-failed-save not ported: its main case (locked data) is covered by load retry + pending widget taps, and it would rewrite every save path |
| — | Smaller fixes | `chat-session` / `install-claude-code-tool` | ✅ load retry on foreground, 44pt touch targets, guide mockup language, Assistant hours filter + routing. Already on `main`: day-summary edit button, weekly labels, Watch history, splash entrance, sign-up code-expired |
| A1 | Multi-workplace UI (model + persistence exist, no UI) — roadmap lists multi-job as a non-goal | `main` | ❓ owner's choice |
| — | Alternative app icon (hourglass between mountains + tiny worker) | `project-thread` 787d2e9 | ❓ owner's choice (current: neon hourglass, B5) |
| — | Six-month trend chart also on Home | `project-thread` cd28a75 | ❓ owner's choice |

## Final phase — Integration review (after all phases + owner approval)

Before merging, one end-to-end pass to make sure nothing conflicts:

- **Behaviour conflicts between features** — e.g. break (paid/unpaid) × default
  break × manual entry × overtime/tax math; widget/Watch/Live Activity/in-app
  actions arriving at the same time; shift reminders × geofence reminders ×
  break reminders (no duplicate or contradictory notifications).
- **Code conflicts** — recovered branches vs. new work (no duplicated types,
  dead code, or two implementations of the same thing); every shared file still
  compiles in each target (app, widget, Watch, tests).
- **Data** — every new field decodes from old saved data, round-trips through
  CloudKit / account backup / full export-import, and syncs to Watch/widgets.
- **Against the owner's requests** — walk this plan item by item and confirm
  each request is implemented as agreed (and nothing agreed was dropped).
- **Localization** — every new string exists in he / ar / en; RTL layouts.
- **Quality gates** — CI green (build, unit tests, SwiftLint, secret scan),
  privacy docs updated for any new data (Phase 6), then a device test
  checklist for the owner.

## Notes

- This environment has no Xcode; builds are verified by CI, device testing by the owner.
- More requests may be added as the owner remembers them.
- Notifications screen holds the break, shift-reminder and announcements switches. Location reminders stay in their own section for now.
