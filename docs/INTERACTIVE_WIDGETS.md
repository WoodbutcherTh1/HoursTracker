# Interactive Widgets (Agent 6)

## App Group

All of these targets use **`group.com.hourstracker.app`** (same ID as `WatchSharedStore.appGroupID`):

| Target | Entitlements |
|--------|----------------|
| HoursTracker (iOS) | `HoursTracker/HoursTracker.entitlements` |
| HoursTrackerWidgets (iOS) | `HoursTrackerWidgets/HoursTrackerWidgets.entitlements` |
| HoursTrackerWatch | `HoursTrackerWatch/HoursTrackerWatch.entitlements` |
| HoursTrackerWatchWidgets | `HoursTrackerWatchWidgets/HoursTrackerWatchWidgets.entitlements` |

Phone `pushWatchSnapshot()` mirrors into the App Group and reloads WidgetKit timelines.

## Shared intents (`HoursTrackerKit`)

| Intent | Role |
|--------|------|
| `ClockInIntent` / `ClockOutIntent` / `ToggleClockIntent` | Optimistic App Group mutate via `WidgetClockService` → `SharedClockApplicator` + enqueue `WidgetPendingEventStore`. Phone drains with `applyWatchClockEvent` (same path as WatchConnectivity). |
| `QuickExportIntent` | Path **A**: CSV + notification Share. Path **B**: marks App Group flag; `openAppWhenRun` is computed from that flag so the host app opens. Returns **only** `.result(dialog:)` (no `OpensIntent`) to avoid opaque-type mismatches. |
| `OpenExportReadyIntent` | Standalone “Open Export” shortcut / hand-off; same flag-driven `openAppWhenRun`. |

## Surfaces

- **iOS** `HoursStatusWidget`: Small (toggle) + Medium (toggle + Export).
- **watchOS** `ClockStatusWidget`: `Button(intent: ToggleClockIntent())` on complication families.

## Export hand-off

1. **A** — notification category `HT_QUICK_EXPORT`, action `HT_SHARE_EXPORT` → app presents share sheet for the App Group CSV.
2. **B** — before scheduling, check `UNUserNotificationCenter` authorization; if `.denied`, never schedule; open Export instead.

## Mac verify (required before merge)

1. `xcodegen generate && xcodebuild …`
2. Install app once (seeds App Group snapshot).
3. Add Small + Medium widgets; tap Clock In/Out.
4. Medium Export with notifications allowed → banner → Share.
5. Deny notifications → Export opens app on Export with CSV share.
6. Watch complication toggle while phone locked / unlocked.

Preview mockups (demo data only): `/opt/cursor/artifacts/widget-previews/`.
