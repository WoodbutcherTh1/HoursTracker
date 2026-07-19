# Watch Clock door — rebuild checklist (Part B)

## What you saw vs what the code is

| Symptom on device | Meaning |
|-------------------|---------|
| Pill / capsule with `כניסה` / `יציאה` | **Old binary** — `.borderedProminent` + `.tint(.green/.orange)` |
| Green → **orange** | **Old binary** — system `.orange` |
| Circular door, green → **red** | New `WatchCircularDoorButton` installed |

Part A (sync) can work with a **new iPhone build + old watch build**. That is why sync looked fixed while the Clock UI stayed the old pill.

## Files touched

| File | Role |
|------|------|
| `HoursTrackerWatch/ClockScreenView.swift` | **Primary.** Replaced pill `Button` with `WatchCircularDoorButton` (circle + door glyph). |
| `HoursTrackerKit/.../SharedClockDoorButton.swift` | iPhone Home red bumped to same true-red RGB. |

### Color values

| State | Old (device you saw) | New |
|-------|---------------------|-----|
| Ready to clock in | SwiftUI `.green` (system) | `Color(red: 0.15, green: 0.95, blue: 0.45)` |
| Ready to clock out | SwiftUI `.orange` ≈ (1.0, 0.58, 0.0) | `Color(red: 0.92, green: 0.10, blue: 0.16)` **true red** |

### How to confirm the new build

Accessibility id: `watch.clock.door` (was `watch.clock.toggle` on the pill).

## Install — full rebuild required (no hot reload)

Watch UI changes need a **full install** of the watch app. SwiftUI Previews / “refresh” do **not** update a physical Apple Watch.

On Mac:

```bash
cd /path/to/HoursTracker
git fetch && git checkout cursor/watch-iphone-sync-clock-ad5d
xcodegen generate   # if you use XcodeGen
```

In Xcode:

1. Scheme: **HoursTracker** (or HoursTrackerWatch) with destination = your paired watch / “iPhone + Watch”.
2. **Product → Clean Build Folder**
3. Run / install so **both** iPhone and Watch apps update (watch often lags if only the phone target is run).
4. On the watch: force-quit HoursTracker, reopen Clock — you must see a **circle with a door**, not a text pill.

If you still see the pill, the watch is still running the old app — check Xcode’s install destination includes the Watch.
