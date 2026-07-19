# Install watch door build **b14** (required)

If the watch still shows a green/orange **text pill**, the watch is **not** running this code.

## Proof on device

After a correct install, Clock screen must show:

1. A **filled circle** (green when out, **red** when in) with a **door SF Symbol**
2. Tiny text **`b14`** under the summary line

If you do **not** see `b14`, stop — you are still on the old watch app.

## Exact Mac steps

```bash
cd /path/to/HoursTracker   # your local clone
git fetch origin
git checkout cursor/watch-iphone-sync-clock-ad5d
git pull origin cursor/watch-iphone-sync-clock-ad5d
# confirm:
git rev-parse --short HEAD   # should include fc0d527 or later (door commits)
grep -n 'b14' HoursTrackerWatch/ClockScreenView.swift
xcodegen generate            # REQUIRED if the repo uses project.yml
```

Xcode:

1. Open the **generated** `HoursTracker.xcodeproj` (not an old copy elsewhere).
2. Scheme: **HoursTracker** (embeds Watch) **or** **HoursTrackerWatch**.
3. Destination: your **physical iPhone** (Watch installs as companion) — or pick the Watch directly.
4. **Product → Clean Build Folder** (⇧⌘K).
5. **Product → Run** (⌘R). Wait until Xcode says the Watch app finished installing.
6. On the Watch: double-click crown → force-quit HoursTracker → open again.

## Common mistakes

| Mistake | Result |
|---------|--------|
| Built iPhone only / old scheme | Sync works, pill UI stays |
| Didn’t `git pull` this branch | Local Mac still has pill code |
| Skipped `xcodegen generate` | Xcode project may be stale |
| Hot reload / Preview | **Never** updates a real Watch |
| Looking at Watch face complication | That’s widgets — open the **Watch app** Clock tab |

## Colors in b14

- Out / clock-in ready: `RGB(0.12, 0.82, 0.38)` green circle + `door.left.hand.closed`
- In / clock-out ready: `RGB(0.95, 0.08, 0.14)` red circle + `door.left.hand.open`
