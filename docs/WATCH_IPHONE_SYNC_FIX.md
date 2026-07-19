# Watch → iPhone Sync Fix (Agent 7)

## Root cause

1. **Reachable path was not durable:** when `WCSession.isReachable == true`, watch clock events used `sendMessage` only and queued `transferUserInfo` **on failure**. A killed / non-processing iPhone could miss the event while the watch still showed an optimistic Recent Shifts row.
2. **App Group hand-off missing for Clock screen:** phone cold-launch drain only read `WidgetPendingEventStore`. Watch **Clock** taps wrote to Documents `WatchPendingActionQueue` + WCSession — **not** the App Group file the phone drains.
3. **Unmerged snapshot persist:** watch WCSession handler saved raw phone snapshots into App Group before merging pending (complication flicker / race).

## Fix

| Change | Effect |
|--------|--------|
| Always `transferUserInfo` (+ `sendMessage` when reachable) | Survives killed iPhone; flushes when Bluetooth returns |
| Watch `sendClockEvent` → `WidgetPendingEventStore` + App Group pending queue | Phone `drainWidgetPendingEvents` on launch / `configureWatchBridge` |
| Drain App Group **before** first `pushWatchSnapshot` | Stale snapshot cannot race ahead of recovered clocks |
| `os.Logger` / `WatchSyncLog` category `WatchSync` | Verify `applyWatchClockEvent ENTER/OK` on device |
| Shared `SharedClockDoorButton` in Kit | Watch Clock matches iPhone Home door (scaled) |

## Device verify (required)

1. Pair watch + iPhone, Bluetooth on.
2. Force-quit HoursTracker on iPhone.
3. Clock in **and** out on watch Clock screen (door).
4. Confirm shift under watch אחרונים / Recent.
5. Open iPhone app → History must show the shift with no extra tap.
6. Console filter: subsystem `com.hourstracker.app`, category `WatchSync` — expect `applyWatchClockEvent OK`.
7. Repeat with Bluetooth off during clock, then re-enable — queued sync must land.

**Do not merge on text/screenshot alone — real-device eye check required (project rule).**
