# HoursTracker Security Hardening Log

Running phase reports for the App Store enterprise hardening work. Newest phase at the bottom.

---

## Phase 1 — Data at rest & complete deletion (A1–A5)

**Date:** 16 July 2026  
**Status:** Complete — tests green; waiting for user `"continue"` before Phase 2.

### (a) Tasks completed

| Task | Summary |
|---|---|
| **A1** | All persisted JSON (sessions, settings, activity log) and export temp files written via `ProtectedFileWriter` (`.atomic` + `.completeFileProtectionUnlessOpen`). First-launch migration rewrites existing files. Activity log persist failures surfaced via `os.Logger` (private). Injectable `FileWriting` seam for tests. |
| **A2** | National ID moved to Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). JSON + CloudKit settings payload store empty `workerIDNumber`. In-memory API unchanged. Migration from legacy JSON. Documented Keychain (not CryptoKit) decision in `docs/ARCHITECTURE.md`. |
| **A3** | GPS coordinates removed from `applyLocation` activity log details. First-load scrub strips coordinate-like details from historical `location` entries. Audited other log call sites (timestamps/counts/format identifiers only). |
| **A4** | Exports go to `tmp/Exports/` with protection (`ExportTempFileStore`). Share sheet deletes file on completion; directory wiped on launch, background, and delete-all. |
| **A5** | `deleteAllUserData` now clears export temps, pending/delivered notifications, Keychain ID (via settings reset), and purges CloudKit sessions + settings record when sync is supported; partial cloud failure surfaces a localized error. Confirmation copy mentions iCloud. |

### (b) Files changed and why

| File | Why |
|---|---|
| `HoursTracker/Utilities/ProtectedFileWriter.swift` | **New** — protected write helper + migration helpers |
| `HoursTracker/Utilities/KeychainStore.swift` | **New** — Security-framework Keychain for national ID |
| `HoursTracker/Utilities/ExportTempFileStore.swift` | **New** — protected export temp directory + wipe |
| `HoursTracker/Managers/PersistenceManager.swift` | Protected writes, Keychain ID load/save/migrate |
| `HoursTracker/Managers/ActivityLogStore.swift` | Protected writes, logged persist failures, coordinate scrub, export via temp store |
| `HoursTracker/Managers/CloudKitSyncManager.swift` | Strip ID from settings upload; keep local ID on merge; `purgeUserCloudData` |
| `HoursTracker/Managers/SyncingPersistenceStore.swift` | `saveSettingsLocally`, `purgeCloudData` |
| `HoursTracker/Managers/ExportManager.swift` | Write reports into Exports/ |
| `HoursTracker/Utilities/ZipWriter.swift` | DOCX archive uses protected writer |
| `HoursTracker/ViewModels/AppViewModel.swift` | No GPS in log; complete delete-all |
| `HoursTracker/HoursTrackerApp.swift` | Wipe exports on launch/background |
| `HoursTracker/Views/ExportView.swift` | ShareSheet completion deletes export URLs |
| `HoursTracker/Utilities/L10n.swift` + `Localizable.xcstrings` | iCloud delete confirm + cloud partial-failure string |
| `docs/ARCHITECTURE.md` | Keychain decision, protected persistence, delete-all scope |
| `HoursTrackerTests/*` | New/updated tests for A1–A5 behaviors |
| `docs/HARDENING_LOG.md` | **New** — this log |

### (c) Verification

**Automated (all green):**
```
xcodegen generate
xcodebuild test -project HoursTracker.xcodeproj -scheme HoursTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```
102 tests, 0 failures. New/updated coverage includes:
- `ProtectedFileWriterTests`
- `WorkerIDKeychainPersistenceTests`
- `ExportTempFileStoreTests`
- `ActivityLogStoreTests` (scrub + Exports path)
- `AppViewModelTests` (delete-all + cloud purge failure)
- `SyncingPersistenceStoreTests` (local settings save, purge)
- `SyncMergeTests` (national ID never taken from remote)

**Manual (Phase 1 Part D) — performed/simulatable via tests; device container inspection recommended by submitter:**
- [x] ID omitted from JSON after save (unit-tested); Keychain rehydrates in-memory API
- [x] Export files land under `Exports/` with protected write options; wipe empties directory
- [x] Delete-all clears sessions/settings/log path, export temps, notifications API calls, Keychain via settings reset, and requests CloudKit purge when supported
- [ ] Physical device container inspection of `NSFileProtectionCompleteUnlessOpen` on Documents JSON (simulator attribute reporting is unreliable; options seam is tested)

### (d) Skipped / deferred / discoveries

- **Simulator file-protection attributes** often do not report `.completeUnlessOpen` reliably on `tmp`; tests assert `ProtectedFileWriter.writingOptions` and treat attributes as best-effort when present. Verify on a real device before submission.
- **National ID does not sync across devices** (ThisDeviceOnly Keychain). Intentional; documented in ARCHITECTURE.
- **CloudKit `deleteSessions` during normal saves** still fire-and-forget; delete-all uses throwing `purgeUserCloudData` for settings + sessions. Tombstones / conflict handling remain Phase 3 (A9).
- **Privacy manifest / policy wording** about iCloud and background location left for Phases 2–3 so Phase 1 stays scoped.
- Log call-site audit: remaining details are ISO timestamps, hour counts, overwrite counts, and export format/language identifiers — acceptable per A3.

### (e) Next phase preview

**Phase 2 (A6–A8):** Remove `UIBackgroundModes: location` and `allowsBackgroundLocationUpdates`; stage When-In-Use → Always permission with Settings denial UI; add explicit off-by-default iCloud sync toggle so `syncNow`/uploads no-op without consent.

---

## Phase 2 — Location & permissions (A6–A8)

**Date:** 16 July 2026  
**Status:** Complete — tests green; waiting for user `"continue"` before Phase 3.

### (a) Tasks completed

| Task | Summary |
|---|---|
| **A6** | Removed `UIBackgroundModes: location` from `project.yml` + `Info.plist`. Removed `allowsBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically = false`, and stray `stopMonitoringSignificantLocationChanges`. Removed deprecated `NSLocationAlwaysUsageDescription`. Documented that region monitoring relaunches the app without background-location mode. |
| **A7** | Staged arrival-reminder flow: notifications callback → When-In-Use → Always. `LocationCaptureHelper` waits for authorization before `requestLocation`. Settings shows denial rows for location/notifications with deep-link to system Settings. |
| **A8** | Added `CloudSyncPreference` (`iCloudSyncEnabled`, default off). `syncNow` / uploads / remote deletes no-op unless enabled. Settings toggle with explanation; turning off offers keep vs delete iCloud copies. Updated `docs/PRIVACY.md` + ARCHITECTURE. |

### (b) Files changed and why

| File | Why |
|---|---|
| `project.yml` / `Info.plist` | Drop background location mode + deprecated Always key; keep display name/version under xcodegen |
| `LocationReminderManager.swift` | Staged auth; no background-location APIs; permission status API |
| `LocationCaptureHelper.swift` | Wait for When-In-Use before `requestLocation` |
| `CloudSyncPreference.swift` | **New** — user opt-in persistence |
| `SyncingPersistenceStore.swift` | Gate cloud ops on preference |
| `AppViewModel.swift` | Sync guard, disable+purge, published permission status |
| `SettingsView.swift` | Denial UI + iCloud toggle / disable dialog |
| `L10n.swift` + `Localizable.xcstrings` + `InfoPlist.xcstrings` | New/updated strings (en/he/ar) |
| `docs/PRIVACY.md`, `docs/ARCHITECTURE.md` | Truthful location + iCloud opt-in wording |
| `HoursTrackerTests/LocationPermissionFlowTests.swift` | **New** |
| `HoursTrackerTests/CloudSyncPreferenceTests.swift` | **New** |
| Test doubles / SyncingPersistenceStoreTests | Preference injection |

### (c) Verification

```
xcodegen generate
xcodebuild test -project HoursTracker.xcodeproj -scheme HoursTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```
**112 tests, 0 failures.**

Manual Phase 2 items (simulator):
- [x] Info.plist has no `UIBackgroundModes: location` / no `NSLocationAlwaysUsageDescription` (asserted in tests)
- [ ] Device: enable arrival reminders → staged prompts → geofence entry notification without background location mode (requires physical device)
- [x] Sync toggle default off; uploads gated (unit-tested)

### (d) Skipped / deferred / discoveries

- **UserDefaults** used for `iCloudSyncEnabled` — Phase 3 **must** add `NSPrivacyAccessedAPITypes` reason `CA92.1`.
- In-app `PrivacyPolicyView` string catalog still has older “background location” wording in places; Phase 3 A10 will fully reconcile policy strings with `docs/PRIVACY.md`.
- Geofence-while-terminated cannot be fully automated on simulator; code comment documents region-monitoring relaunch behavior.

### (e) Next phase preview

**Phase 3 (A9–A10):** CloudKit tombstones + conflict handling + serialized uploads; truthful privacy manifest (“data not collected”) and aligned privacy-policy / display-name consistency; declare UserDefaults accessed-API reason.

---

## Phase 3 — CloudKit correctness & privacy declarations (A9–A10)

**Date:** 16 July 2026  
**Status:** Complete — tests green; waiting for user `"continue"` before Phase 4.

### (a) Tasks completed

| Task | Summary |
|---|---|
| **A9** | Session deletion tombstones (`SessionTombstoneStore`); merge never resurrects tombstoned IDs; sync deletes stale remote tombstones; `CKModifyRecordsOperation` + `.changedKeys` with `serverRecordChanged` LWW retry; `CloudWriteQueue` serializes uploads/deletes; CloudKit entitlements documented via `docs/HoursTracker.entitlements.cloudkit.example` (personal-team entitlements stay empty). |
| **A10** | Privacy manifest: empty collected types + `NSPrivacyTracking=false` + UserDefaults `CA92.1`; `docs/PRIVACY_MANIFEST.md` reasoning; reconciled `docs/PRIVACY.md` + in-app policy strings (incl. iCloud section); display name unified to **HoursTracker**. |

### (b) Files changed (high level)

- `SessionTombstoneStore.swift`, `CloudWriteQueue.swift` (new)
- `CloudKitSyncManager.swift`, `SyncingPersistenceStore.swift`
- `PrivacyInfo.xcprivacy`, `docs/PRIVACY_MANIFEST.md`, `docs/HoursTracker.entitlements.cloudkit.example`
- Privacy / brand strings (`Localizable.xcstrings`, `InfoPlist.xcstrings`, `project.yml`, `Info.plist`, `PRIVACY.md`, `README.md`, activity-log titles)
- `PrivacyPolicyView.swift`, `L10n.swift`, `ARCHITECTURE.md`
- Tests: SyncMerge, SyncingPersistenceStore, SessionTombstoneStore, CloudSyncPreference

### (c) Verification

```
xcodegen generate
xcodebuild test … iPhone 16, OS=18.3.1
```
**118 tests, 0 failures.**

Manual: PrivacyInfo / PRIVACY.md / in-app strings describe the same opt-in iCloud + no developer collection story; display name is HoursTracker across plist/catalogs.

### (d) Skipped / deferred / discoveries

- Live CloudKit conflict/tombstone behavior still needs a dual-device check on a paid-team CloudKit build (not available in personal-team CI).
- XML comments were kept out of `PrivacyInfo.xcprivacy` (reasoning lives in `docs/PRIVACY_MANIFEST.md`) for safer App Store ingestion.

### (e) Next phase preview

**Phase 4 (A11, A12, A14–A16):** CSV/formula injection + XML/Markdown escaping; bounded imports; pasteboard hygiene; os_log privacy sweep; settings validation/clamping.

---
