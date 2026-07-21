# Data-loss incident — 2026-07-19 (real device)

**Severity:** Critical — production History + Settings wiped on a real user device.  
**Status:** Root cause assessed from git; device container not available in this cloud environment (recovery steps for Mac below).

---

## What the user saw

After adding the App Groups capability to Watch/iOS targets and re-running on a physical iPhone, **all prior History months and worker settings were gone**. Only ~3 sessions from the same day (19.07) remained.

---

## Git facts (verified)

### Entitlements changed today (commit `4a011c6`)

| Target | Before | After |
|--------|--------|--------|
| `HoursTracker/HoursTracker.entitlements` | empty `<dict/>` | App Group `group.com.hourstracker.app` |
| `HoursTrackerWatch/HoursTrackerWatch.entitlements` | empty → then App Group | App Group |
| Watch/iOS widget entitlements | same pattern | App Group |

### Bundle identifiers

**iOS app `PRODUCT_BUNDLE_IDENTIFIER` stayed `com.hourstracker.app`.** No CFBundleIdentifier change for the phone app in today’s diffs. Watch targets use `com.hourstracker.app.watchkitapp` (unchanged after first Watch add).

### Persistence (not Core Data / SQLite)

Local store is JSON in the app sandbox Documents directory:

- `work_sessions.json`
- `workplace_settings.json` (national ID in **Keychain**, not JSON)
- `activity_log.json`
- tombstones JSON

There is **no** automatic rolling backup of these files prior to this Agent 8 work.

### CloudKit

`HTCloudKitEnabled` defaults **false**; personal-team builds use `NoOpCloudSyncManager`. CloudKit was **not** a live recovery source for this install unless the user had previously enabled iCloud sync on a CloudKit-capable build (unlikely for this device).

---

## Root-cause assessment

### Hypothesis A — Entitlement / provisioning reinstall (most likely for “everything wiped”)

Adding App Groups changes the provisioning profile / signing surface. Xcode on a physical device often performs a **clean install** (“Uninstalling and Installing…”) when the signed entitlements change substantially, which **destroys the app sandbox** (Documents JSON + typically Keychain items for that app).

That matches: empty History + defaulted Settings, with only *new* sessions created after reinstall.

**Cloud agent cannot see the user’s Xcode build log.** On the Mac that ran to the device, check:

`Window → Devices and Simulators` / Report navigator for the Run — look for **“Uninstalling”** before Install. If present → hypothesis confirmed.

### Hypothesis B — App Group alone moved data (unlikely)

App Groups add a *shared* container; they do **not** relocate Documents. Code still reads/writes Documents via `PersistenceManager`. Merely adding the entitlement without reinstall would **not** empty Documents.

### Hypothesis C — Corrupt quarantine emptied the store (possible secondary)

If `work_sessions.json` failed to decode once, `CorruptFileQuarantine` renames it to `work_sessions.json.corrupt` and the app starts empty. That would **not** usually wipe Settings at the same time unless both files failed. Still worth downloading the container (below).

---

## Recovery checklist (Mac + device — do before any further reinstall)

1. **Do not delete the app again.**
2. Xcode → **Window → Devices and Simulators** → select iPhone → HoursTracker → **Download Container**.
3. Inside the `.xcappdata` package inspect:
   - `AppData/Documents/work_sessions.json`
   - `AppData/Documents/workplace_settings.json`
   - Any `*.corrupt` / `*.corrupt.<timestamp>` sidecars
   - App Group container (if present under Group Containers) for `group.com.hourstracker.app`
4. If a `.corrupt` sidecar has the old sessions, copy it aside and Agent 8 restore / manual JSON restore can re-import.
5. Partial manual fallback (user already has): July PDF export + June pay-slip photo → Camera OCR / blank grid.

---

## Prevention (Agent 8)

- Lossless **Full Backup** JSON export/import in Settings.
- Silent rolling backups (App Group + Documents), last 10–14 copies.
- Pre-replace snapshot before any restore overwrite.
- See `docs/BACKUP_STRATEGY.md`.
