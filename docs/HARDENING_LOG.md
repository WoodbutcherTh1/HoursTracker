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
