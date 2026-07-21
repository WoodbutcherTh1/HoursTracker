# Siri Shortcuts — Clock In / Out (Agent 11)

Builds on Agent 6 App Intents in `HoursTrackerKit` (`ClockInIntent`, `ClockOutIntent`, `ToggleClockIntent` → `WidgetClockService` → App Group snapshot).

## What was added

| Piece | Role |
|-------|------|
| `HoursTrackerAppShortcuts` | `AppShortcutsProvider` with en / he / ar phrases |
| `ClockIntentDialogCopy` | Short Siri dialogs using snapshot language + clock time |
| Intent `openAppWhenRun = false` | Parameter-free; no app UI required |

No new clock-in/out math — same `WidgetClockService` / `SharedClockApplicator` path as widgets.

## Phrases (examples)

- EN: “Clock in with HoursTracker”, “Clock out with HoursTracker”
- HE: “כניסה עם HoursTracker”, “יציאה עם HoursTracker”
- AR: “سجل دخول مع HoursTracker”, “سجل خروج مع HoursTracker”
- Toggle uses explicit “in or out” / “כניסה או יציאה” / “الدخول أو الخروج”

## Feedback

- Success: “Clocked in at 07:20” (localized)
- Rest day success: prefixes “Rest day — …” (same `clockIn` rules; not silent)
- Already open: “Already clocked in since …” — **no duplicate session**
- Missing snapshot: ask user to open the app once

## Device acceptance

1. Open HoursTracker once (seeds App Group).
2. iPhone: “Hey Siri, Clock in with HoursTracker” → dialog + Home/widget update.
3. Watch: same phrase via watch Siri.
4. Repeat Clock in while open → explanatory rejection, not a second shift.

`HoursTrackerAppShortcuts` lives in **HoursTrackerKit**, linked by both iPhone and Watch apps.
