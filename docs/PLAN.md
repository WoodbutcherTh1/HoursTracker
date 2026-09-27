# HoursTracker — Work Plan (2026-09)

Agreed with the owner in a planning session. Each item lands as its own commit
on `claude/planning-requests-bb6hz1`. Status: ⬜ todo · 🟡 in progress · ✅ done.

## Phase 1 — Recover lost work (branches never merged into `main`)

| # | Item | Source branch | Status |
|---|------|---------------|--------|
| B2 | Prevent cloud sync from silently erasing data | `claude/jolly-wright-6ep32d` | ⬜ |
| B1 | Forgot-password flow (code-based reset) | `claude/jolly-wright-6ep32d` | ⬜ |
| B3 | Widget interactivity, Watch hours display, Live Activity staleness | `claude/jolly-wright-6ep32d` | ⬜ |
| B4 | Watch app showing raw localization keys | `claude/jolly-wright-6ep32d` | ⬜ |
| B5 | Neon hourglass app icon (iPhone + Watch) | `claude/jolly-wright-6ep32d` / `claude/neon-app-icon` | ⬜ |
| B12 | Assistant: honour cloud opt-out, visibility toggle | `assistant-review-fixes` | ⬜ |
| B13 | Timeout on CloudKit sync so a hang surfaces as failed | `claude/agitated-mestorf-e371c0` | ⬜ |
| B14 | In-app language override actually changes language | `claude/fix-in-app-language-resolution` | ⬜ |

## Phase 2 — Break button ("יצאתי להפסקה") — C1

- Session records break intervals (start/end); `breakMinutes` derived from them;
  old sessions keep decoding.
- Settings: target break length (default 30 min). A recorded break suppresses
  the automatic `defaultBreakMinutes` deduction.
- Home: "Start break" next to the door while clocked in; countdown
  ("12 of 30 min left"); "Back to work".
- Local notification when the target break length ends.
- Fully synced: app, Watch, widgets, Live Activity / Dynamic Island — break
  can be started/ended from any of them.

## Phase 3 — Live hours/money counter everywhere — C3

- App, Watch, widgets and Dynamic Island all derive from the same clock-in
  time so the numbers match.
- Hours tick every second everywhere (system timer text in widgets / Live
  Activity). Money ticks every second in app + Watch; in widgets / Live
  Activity it refreshes as often as the system allows (Apple does not allow
  per-second computation there).

## Phase 4 — History swipe behaviour — C4

- Swipe on the week strip / arrows row → move one **week**.
- Swipe inside the full-history (expanded) grid → move one **month** (payroll period).
- The period title header stays pinned and never disappears during the
  transition (bug seen moving 9 → 8).

## Phase 5 — Shift reminders by usual schedule — C2

- Learn usual clock-in / clock-out time **per weekday** from past sessions.
- Notify **5 min before** the usual start ("don't forget to clock in") and
  5 min before the usual end ("don't forget to clock out").
- Cancelled automatically when already clocked in / out. No location needed;
  skip rest days; on/off toggle in Settings. Existing geofence reminders stay.

## Phase 6 — Owner/Admin dashboard — C5

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

## Phase 7 — Remaining recovered work

| # | Item | Source |
|---|------|--------|
| B6 | 6-month hours/pay trend chart | `install-claude-code-tool` / `project-thread-dslh5m` |
| B7 | Payslips as its own tab | `install-claude-code-tool` |
| B8 | Lock Screen widget | `chat-session` / `install-claude-code-tool` |
| B9 | History header tap toggles (date, net/gross) | `chat-session` / `project-thread-dslh5m` |
| B10 | CSV-column-aware timesheet importer | `chat-session` |
| B11 | Icon-led Settings section headers | `project-thread-dslh5m` |
| B15 | Full backup/restore + rolling auto backups | `cursor/full-backup-restore*` |
| B16 | Monthly payroll-period overview ring | `cursor/history-monthly-overview` |
| B17 | Older Cursor fixes (sync race, rollback on failed persist, scanner parsing…) — verify each still applies | `cursor/*` |
| A1 | Multi-workplace UI (model + persistence exist, no UI) — decide first; roadmap lists multi-job as a non-goal | `main` |

## Notes

- This environment has no Xcode; builds are verified by CI, device testing by the owner.
- More requests may be added as the owner remembers them.
