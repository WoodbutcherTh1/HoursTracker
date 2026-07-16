# Cursor Prompt — Enterprise Security & Privacy Hardening for HoursTracker

Copy everything below the line into Cursor as a single instruction.

---

You are acting as a **senior iOS security engineer** preparing this app for App Store submission. Your task is to harden HoursTracker's security and privacy to enterprise level. This is an offline-first SwiftUI app (iOS 17+, no third-party dependencies, no networking layer) that stores highly sensitive personal data: the user's full name, **Israeli national ID number (teudat zehut)**, employee number, precise workplace GPS coordinates, marital/family status, pay rates, and full work history.

**Hard rules for the whole task:**

- Do NOT add any third-party dependency. Use only Apple frameworks (CryptoKit, LocalAuthentication, Security/Keychain, os.log, etc.).
- Do NOT add any networking, analytics, telemetry, or crash-reporting SDK. The app must stay fully offline (CloudKit private database is the only permitted remote store, and only behind the existing opt-in build flag).
- Do NOT change payroll/overtime/tax calculation logic (`OvertimeCalculator`, `IsraeliTaxEstimator`, `TaxCreditPointsCalculator`, `HistoryPeriodHelper`).
- Every new user-facing string must be localized through `HoursTracker/Resources/Localizable.xcstrings` (English, Hebrew, Arabic) and used via the existing `L10n` pattern in `HoursTracker/Utilities/L10n.swift`.
- Keep the project buildable via `xcodegen generate` and keep the full test suite green (`xcodebuild test -project HoursTracker.xcodeproj -scheme HoursTracker -destination 'platform=iOS Simulator,...'`). Add tests for every behavior change listed below.
- **Encryption must stay transparent to in-app reads.** Every piece of stored user data (JSON stores, Keychain-held fields, activity log) must remain readable in full, at runtime, through the existing store interfaces (`PersistableStore` / `SyncingStore`, `WorkplaceSettings`, `ActivityLogStore`). Never create write-only storage, never scatter decryption logic into individual consumers (e.g. only inside an export renderer), and never make the complete data set impossible to enumerate through those interfaces. Protection classes and Keychain are for the at-rest layer only; the domain layer above them keeps working with plain values.
- Work through the phases in order, respecting the guardrails in Part C. Verify with Part D.

---

## Execution protocol — phased, with mandatory stop points

The work is split into **6 phases** (mapped onto the tasks in Parts A and B below). Follow this protocol strictly:

1. **Do exactly one phase at a time.** After finishing a phase, STOP. Do **not** start the next phase until the user explicitly replies **"continue"**. This is a hard rule — no exceptions, even if the next phase seems trivial.
2. **At the end of every phase, before stopping:**
   - Run `xcodegen generate` and the full test suite; everything must be green (including the new tests you added in that phase).
   - Run the manual verification items from Part D that are tagged with that phase.
   - Commit the phase's work as one or a few small, logically separated commits.
   - Post a **phase report** in the chat AND append it to a running `docs/HARDENING_LOG.md` file (create it in Phase 1). The report must contain: (a) which tasks were completed, (b) every file changed and why, (c) how it was verified — test names run and manual checks performed, (d) anything you skipped, deferred, or discovered along the way (new issues found go here too), (e) a one-paragraph preview of the next phase.
3. **If anything is red, ambiguous, or riskier than described at a checkpoint, stop and ask** — do not "fix forward" into the next phase.
4. **After the final phase**, write `docs/HARDENING_SUMMARY.md`: an executive summary table mapping every finding → fix → verification evidence, a list of residual risks / accepted trade-offs, and the manual App Store steps the user must still do themselves (fill the App Privacy questionnaire to match `PrivacyInfo.xcprivacy`, host the privacy policy at a public URL for App Store Connect, verify the Data Protection entitlement on a real-device build).

**The phases:**

| Phase | Scope | Tasks |
|---|---|---|
| **1** | Data at rest & complete deletion (highest risk) | A1, A2, A3, A4, A5 |
| **2** | Location & permissions (App Review blocker) | A6, A7, A8 |
| **3** | CloudKit correctness & truthful privacy declarations | A9, A10 |
| **4** | Input/output hardening (injection, imports, pasteboard, logs, validation) | A11, A12, A14, A15, A16 |
| **5** | App Lock & screen privacy | A13 |
| **6** | CI, supply chain & security docs | A17 + all of Part B |

---

## Part A — Specific, verified issues to fix (in priority order)

### PHASE 1 — Data at rest & complete deletion (A1–A5)

### A1. Encrypt/protect all data at rest (CRITICAL)

**Current:** `HoursTracker/Managers/PersistenceManager.swift` (`save`, lines ~63–71) writes `work_sessions.json` and `workplace_settings.json` to the Documents directory with `Data.write(options: .atomic)` only — no iOS Data Protection class. `HoursTracker/Managers/ActivityLogStore.swift` (`persist()`) does the same for `activity_log.json`. These files contain the national ID, name, GPS coordinates, and full work history in plaintext.

**Required:**
- Write all persisted files with `.completeFileProtectionUnlessOpen` or `.completeFileProtection` (`Data.WritingOptions`). Note the geofence arrival handler can wake the app in the background before first unlock is not an issue here (geofence only fires notifications from in-memory state), but if you find a background read path, use `.completeFileProtectionUntilFirstUserAuthentication` for that specific file and document why.
- Migrate existing files on first launch: read, re-write with protection, verify attributes via `FileManager.attributesOfItem` (`.protectionKey`).
- Apply the same protection to every other file write in the app (activity log, export temp files — see A4).
- `ActivityLogStore.persist()` currently swallows errors with `try?` — surface failures via `os.log` (private) at minimum.
- Add a unit-testable seam so tests can assert the writing options used (e.g., inject a file-writer protocol or verify protection attributes in an integration test).

### A2. Move the national ID number out of plaintext storage (CRITICAL)

**Current:** `WorkplaceSettings.workerIDNumber` (`HoursTracker/Models/WorkplaceSettings.swift`) is a plain `String` serialized into `workplace_settings.json` and, when CloudKit is enabled, uploaded inside the settings record payload (`CloudKitSyncManager.makeSettingsRecord`).

**Required:**
- Store the ID number in the **Keychain** with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (a small internal `KeychainStore` helper using the Security framework; no third-party wrappers). Remove it from the JSON payload and from the CloudKit settings record: encode it as an empty/absent field, and read it back from Keychain on load. Handle migration: on first load after update, if the JSON still contains a value, move it to Keychain and rewrite the JSON without it.
- Keep the field's public API unchanged: after loading, `WorkplaceSettings.workerIDNumber` still carries the plain value in memory, so every current and future consumer reads it the same way — the Keychain indirection lives only inside the persistence layer (load/save), not in view models or renderers.
- Alternatively (if Keychain complicates the sync design too much): encrypt the field with CryptoKit `AES.GCM` using a per-device key held in the Keychain, and store only ciphertext in JSON/CloudKit. Pick one approach, implement it fully, and document the decision in `docs/ARCHITECTURE.md`.
- Data minimization: the ID number is only used in export headers (`ExportManager.headerLines`). Keep the feature, but make sure the export path reads it just-in-time and nothing logs it.
- Make sure `deleteAllUserData()` also removes the Keychain item.

### A3. Stop writing GPS coordinates into the activity log (CRITICAL, one-line data leak)

**Current:** `HoursTracker/ViewModels/AppViewModel.swift`, `applyLocation(_:)` (lines ~381–387) logs the precise workplace coordinates into the persistent, user-exportable activity log: `details: String(format: "%.5f, %.5f", ...)`.

**Required:** Remove coordinates from the log entry (log the event only, e.g. "Workplace location set"). Add a migration/cleanup that scrubs existing `activity_log.json` entries in category `"location"` of coordinate-like details on first launch. Audit every other `ActivityLogStore.shared.log(...)` call site for sensitive payloads in `details` — timestamps and counts are fine; PII, coordinates, and free-text notes are not.

### A4. Clean up and protect export temp files (CRITICAL)

**Current:** `HoursTracker/Managers/ExportManager.swift` (`write(data:extension:)`, lines ~681–686) and `ActivityLogStore.export(format:)` write reports containing name + national ID + pay data to `FileManager.temporaryDirectory` with **no file protection and no cleanup** — files accumulate indefinitely and outlive "Delete All My Data".

**Required:**
- Write export files into a dedicated subdirectory (e.g. `tmp/Exports/`) with complete file protection.
- Delete the file after the share sheet completes: pass a `completionWithItemsHandler` through `ShareSheet` (`HoursTracker/Views/ExportView.swift`) and the share paths in `HistoryView` / `ActivityLogView`, or at minimum delete all files in the exports directory on every app launch and on scene-phase background.
- Build this as one small reusable helper (create protected temp file → share → clean up) rather than logic wired to the current report formats, so any file-producing flow added later automatically gets the same protection and cleanup.
- Wipe the exports directory inside `deleteAllUserData()`.

### A5. Make "Delete All My Data" actually delete everything (App Store Guideline 5.1.1)

**Current:** `AppViewModel.deleteAllUserData()` (lines ~346–359) resets sessions/settings locally, but does **not**: delete CloudKit records, remove export temp files, remove delivered/pending notifications, or clear the Keychain (after A2).

**Required:** Extend it to (1) call `cloud.deleteSessions` for all known session IDs and delete the settings record when sync is supported and available, reporting partial failure to the user; (2) wipe the exports directory (A4); (3) call `UNUserNotificationCenter` `removeAllPendingNotificationRequests()` and `removeAllDeliveredNotifications()`; (4) delete the Keychain item (A2); (5) keep the existing local wipe and geofence teardown. Add a confirmation UI note that iCloud copies are also erased (localized).

### PHASE 2 — Location & permissions (A6–A8)

### A6. Remove the background-location over-grant (biggest App Review risk)

**Current:** `HoursTracker/Info.plist` and `project.yml` declare `UIBackgroundModes: location`, and `LocationReminderManager.locationManagerDidChangeAuthorization` sets `allowsBackgroundLocationUpdates = true`. **Region monitoring (geofencing) needs neither.** This is a genuine privacy over-grant and Apple scrutinizes the `location` background mode heavily.

**Required:**
- Remove `UIBackgroundModes: location` from both `Info.plist` and `project.yml` (keep them in sync — `project.yml` regenerates the project).
- Remove all `allowsBackgroundLocationUpdates` usage and `pausesLocationUpdatesAutomatically = false` from `LocationReminderManager`.
- Remove the stray `stopMonitoringSignificantLocationChanges()` call (nothing ever starts it).
- Remove the deprecated `NSLocationAlwaysUsageDescription` key (iOS 11+); keep `NSLocationAlwaysAndWhenInUseUsageDescription` and `NSLocationWhenInUseUsageDescription`.
- Verify geofence arrival notifications still fire with the app terminated (region monitoring relaunches the app; document this in a code comment).

### A7. Stage the location permission flow properly

**Current:** `LocationReminderManager.requestArrivalReminderPermissions()` requests notifications and `requestAlwaysAuthorization()` in one shot, ignores the notification-auth result, and the UI never reflects denial. `LocationCaptureHelper.capture()` calls `requestWhenInUseAuthorization()` and `requestLocation()` back-to-back (races when not yet authorized).

**Required:**
- Two-stage flow: request When-In-Use first (already granted if the user set a workplace), then Always only when the user enables arrival reminders; after the request, read the actual `authorizationStatus` and surface a localized status row in `SettingsView`'s location section when authorization is denied/restricted (with a button that deep-links to `UIApplication.openSettingsURLString`).
- Handle the notification-authorization callback; if denied, tell the user reminders can't be shown.
- In `LocationCaptureHelper`, wait for `locationManagerDidChangeAuthorization` before calling `requestLocation()` when status is `.notDetermined`.

### A8. Make iCloud sync explicit opt-in (privacy-policy contradiction)

**Current:** `HoursTrackerApp.swift` calls `viewModel.syncNow()` on launch and on every foreground. When a build ships with `HTCloudKitEnabled = true`, user data (including the settings payload) is uploaded automatically with **no user consent toggle** — contradicting `docs/PRIVACY.md` ("data stays on your device unless you later enable iCloud sync").

**Required:** Add a persisted `iCloudSyncEnabled` user setting (default **off**) surfaced in `SettingsView`'s sync section with a localized explanation of what is uploaded and where (user's private iCloud database). `syncNow()`, `uploadSessions`, `uploadSettings`, and `deleteSessions` must all no-op unless the toggle is on. Turning the toggle **off** should offer to delete the already-uploaded iCloud data.

### PHASE 3 — CloudKit correctness & truthful privacy declarations (A9–A10)

### A9. Fix CloudKit sync correctness bugs that resurrect deleted personal data

**Current:** `CloudKitSyncManager.mergeSessions` (lines ~237–249) is a pure union — a session deleted on device A is re-imported from device B on the next sync (deleted personal data comes back: a privacy bug, not just a sync bug). `database.save(record)` has no `serverRecordChanged` conflict handling, so re-uploads of existing records fail silently. `SyncingPersistenceStore.saveSessions` fires an unstructured `Task {}` per save (races/out-of-order uploads). The empty `HoursTracker/HoursTracker.entitlements` lacks the iCloud/CloudKit container entitlement needed when `HTCloudKitEnabled` builds are made.

**Required:**
- Implement tombstones: keep a persisted set of deleted session IDs (with deletion timestamps) so merge never resurrects a locally deleted session; propagate deletions on sync and prune old tombstones.
- Handle `CKError.serverRecordChanged` by re-fetching and re-applying the newer-`modifiedAt`-wins rule; use `CKModifyRecordsOperation` with `.changedKeys`/`savePolicy` appropriately instead of bare `save`.
- Serialize uploads (an `AsyncStream`/actor queue or awaiting the task) so writes can't interleave.
- Document (comment + `docs/ARCHITECTURE.md`) that a CloudKit-enabled build requires adding the `com.apple.developer.icloud-container-identifiers` / CloudKit entitlement for container `iCloud.com.hourstracker.app`; add the entitlement keys guarded so local personal-team builds still work per the existing comments.
- Extend `HoursTrackerTests/SyncMergeTests.swift` to cover deletion tombstones and conflict resolution.

### A10. Make the privacy manifest and privacy policy truthful and consistent

**Current:** `HoursTracker/Resources/PrivacyInfo.xcprivacy` declares five **collected** data types (name, other user content, precise location, photos, diagnostics). Nothing is transmitted to the developer — there is no server and no analytics; CloudKit private-DB storage under the user's own account is not developer "collection" in the App Privacy sense. `NSPrivacyAccessedAPITypes` is an empty array. `docs/PRIVACY.md`, the in-app `PrivacyPolicyView` strings, and the manifest tell three slightly different stories. `Info.plist` display name is "HourTrackers" while the product is "HoursTracker".

**Required:**
- Correct the manifest to reflect reality (for a local-only app with optional private-iCloud sync, the accurate declaration is "data not collected": remove the over-declared collected types, keep `NSPrivacyTracking = false`). Add a comment-doc in `docs/` explaining the reasoning so future features re-evaluate it.
- Audit the code for required-reason APIs (UserDefaults, file timestamps, system boot time, disk space, active keyboards). Today none are used — if any of your changes introduce one (e.g. UserDefaults for the sync toggle or app-lock preference), you MUST add the matching `NSPrivacyAccessedAPITypes` entry with the correct reason code (e.g. `CA92.1` for UserDefaults).
- Reconcile `docs/PRIVACY.md` and `PrivacyPolicyView`/`Localizable.xcstrings` privacy strings with actual behavior after your changes (iCloud opt-in wording, deletion scope including iCloud, no background location mode). Update the "Last updated" date.
- Unify the display name (pick one: "HoursTracker" or "HourTrackers") across `Info.plist`, `project.yml`, privacy docs, and export strings.

### PHASE 4 — Input/output hardening (A11, A12, A14, A15, A16)

### A11. Injection hardening in exports

**Current:** User-controlled strings (workplace name, contractor, worker name, notes, log messages) flow into CSV (`ActivityLogStore.renderCSV`), Markdown, TXT, and DOCX (`ExportManager`). CSV quoting exists but there is **no formula-injection guard** — a value starting with `=`, `+`, `-`, `@`, tab, or CR executes as a formula when the CSV is opened in Excel/Numbers/Sheets. `ExportManager.escapeXML` (lines ~555–560) escapes `&`, `<`, `>` but not `"` and `'`.

**Required:**
- In the CSV renderer, prefix cells that start with `=`, `+`, `-`, `@`, `\t`, or `\r` with a single quote (`'`) (OWASP CSV-injection mitigation), in addition to the existing quoting.
- Extend `escapeXML` to escape `"` → `&quot;` and `'` → `&apos;`.
- Escape pipe characters and leading formatting characters for user-supplied values in the Markdown export table (`ExportManager.exportMarkdown` row values include notes-free fields today, but header lines include names — harden the shared path).
- Add unit tests in `HoursTrackerTests/ExportManagerTests.swift` / `ActivityLogStoreTests.swift` with hostile inputs (`=cmd|' /C calc'!A0`, quotes, pipes, RTL overrides).

### A12. Bound and validate untrusted file imports

**Current:** `TimesheetScannerManager.scan(fileURL:)` reads arbitrary user-picked files with unbounded `Data(contentsOf:)` / `String(contentsOf:)` (memory DoS on a multi-GB file) and trusts the file **extension** rather than content type. `ZipWriter.data(forEntry:)` computes `nameEnd`/`dataStart` ranges without verifying they fit inside the archive before `subdata` (crash on truncated input; test-only today, fix anyway).

**Required:**
- Enforce a size cap before reading (e.g. 50 MB for images/PDFs, 5 MB for text), checked via `FileManager.attributesOfItem(.size)` or `URLResourceValues.fileSize`; return a localized `TimesheetScannerError.fileTooLarge`.
- Validate type via `UTType` conformance (from `URLResourceValues.contentType`) instead of raw extension matching; keep the `fileImporter` allowed-types list in `TimesheetScannerView` consistent.
- Cap PDF page count processed (e.g. 50 pages) to bound OCR work.
- Fix `ZipWriter.data(forEntry:)` bounds checks (`nameEnd`, `dataStart`, and all `uintXXLE(at:)` reads must be verified against `archive.count` before use).

### A14. Pasteboard hygiene

**Current:** `HistoryView.swift:559` copies a shift summary with `UIPasteboard.general.string = ...`, which syncs via Universal Clipboard/Handoff to the user's other devices indefinitely.

**Required:** Use `UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])`.

### A15. os_log privacy annotations

**Current:** `PersistenceManager` and `CloudKitSyncManager` log with `privacy: .public` for filenames, session UUIDs, and error descriptions.

**Required:** Default to `privacy: .private` for identifiers and error payloads (error descriptions can embed user data, e.g. CloudKit record contents). Static category strings may stay public. Sweep every `Logger` call in the codebase.

### A16. Input validation on settings

**Current:** `SettingsView` numeric fields accept anything (negative hourly rate, 0 or absurd geofence radius, negative gas allowance); `WorkplaceSettings` clamps only a few fields on decode.

**Required:** Clamp/validate on save in `WorkplaceSettings`'s initializers and decode path (single source of truth, not just UI): `hourlyRate >= 0`, `dailyGasAllowance >= 0`, `standardDayHours` in (0, 24], `ot125HoursCap >= 0`, `locationRadiusMeters` clamped to [50, 2000] (and still capped by `maximumRegionMonitoringDistance` at geofence time), `numberOfChildren` in 0...15. Optionally validate the Israeli ID checksum client-side and warn (don't block) on mismatch. Add tests.

### PHASE 5 — App Lock & screen privacy (A13)

### A13. Add an optional biometric app lock + screen privacy (enterprise posture)

**Current:** Anyone with the unlocked phone sees the national ID, pay, and full work history; app-switcher snapshots capture it too; the ID is edited via a plain `TextField` in `SettingsView.workerSection`.

**Required:**
- Add an opt-in **App Lock** setting (off by default): when enabled, require Face ID / Touch ID / device passcode (`LocalAuthentication`, `.deviceOwnerAuthentication` policy) on launch and on returning from background after a short grace period (~30 s). Blur/lock the UI until authenticated; handle biometry-unavailable/failure by falling back to passcode; never store any secret yourself — use `LAContext` directly. Localize all strings.
- Add a **privacy overlay** when `scenePhase != .active` (a simple branded redaction view in `HoursTrackerApp`) so app-switcher snapshots don't show PII. Apply regardless of the App Lock setting.
- Mask the ID number at rest in Settings (show it redacted, e.g. `•••••1234`, with an explicit "edit" tap to reveal/change).

### PHASE 6 — CI, supply chain & security docs (A17 + Part B)

### A17. CI / supply-chain hardening

**Current:** `.github/workflows/ci.yml` uses `actions/checkout@v4` (mutable tag), has no `permissions:` block (default token is broad), and runs no static analysis or secret scanning. No `SECURITY.md`.

**Required:**
- Pin all actions to full commit SHAs (with a version comment).
- Add top-level `permissions: contents: read` to the workflow.
- Add jobs (or a second workflow) for: SwiftLint in strict mode with a security-oriented config committed to the repo (installed via Homebrew in CI, not an SPM plugin), and secret scanning (e.g. gitleaks action, SHA-pinned — this is the one permissible CI-only tool exception; if you prefer zero external actions, use `git grep` heuristics and document the limitation).
- Add `SECURITY.md` (supported versions, how to report a vulnerability privately via the support email) and a short `docs/THREAT_MODEL.md` (assets: national ID, location, work history; adversaries: device thief, shoulder surfer, malicious import file, cloud account compromise; mitigations mapped to the items above).

---

## Part B — General enterprise hardening (Phase 6, apply with your own judgment)

1. **Data-protection-by-default:** create one internal helper for all file writes that always applies file protection + atomic writes; forbid raw `Data.write` elsewhere (add a SwiftLint custom rule).
2. **PII inventory:** add `docs/DATA_INVENTORY.md` listing every stored field, where it lives (JSON/Keychain/CloudKit/temp), its protection class, retention, and deletion path. Keep it updated as part of the definition-of-done.
3. **Privacy review gate:** add a PR checklist item (in a `.github/pull_request_template.md`) — "Does this change store, log, export, or transmit new user data? If yes, update the privacy manifest, privacy policy, and data inventory."
4. **Least data in logs:** establish the rule that `ActivityLogStore` never stores PII/coordinates/free-text notes; only event names, counts, durations, and format identifiers.
5. **Crash-safety of persisted data:** keep decode-failure paths non-destructive (today a corrupt JSON silently becomes an empty list — consider quarantining the corrupt file with a `.corrupt` suffix instead of ignoring it, so data is recoverable).
6. **Release checklist:** add `docs/RELEASE_CHECKLIST.md` covering: App Privacy questionnaire answers must match `PrivacyInfo.xcprivacy`; `ITSAppUsesNonExemptEncryption` stays `false` only while using exempt/OS-provided crypto; re-review all permission usage strings; verify Data Protection entitlement/classes on a device build; run the full manual verification in Part D.
7. **Future-proofing:** if any feature ever adds networking, require ATS defaults (no exceptions), certificate-pinning consideration, and a privacy-manifest update — write this down in `docs/ARCHITECTURE.md` so it's a documented gate, not tribal knowledge.

## Part C — Non-goals and guardrails (do NOT do these)

- No analytics, telemetry, crash reporting, ads, or any third-party SDK/network call.
- No server-side components, no accounts/authentication systems.
- No new permission requests beyond what exists (camera, photos, location, notifications).
- Do not enable iTunes/Finder file sharing (`UIFileSharingEnabled`) or document-browser exposure of the Documents directory.
- Do not weaken or bypass existing user-consent flows; do not change payroll/tax math; do not break RTL (Hebrew/Arabic) layouts or localization.
- Do not rewrite architecture wholesale — make targeted, reviewable changes with tests.

## Part D — Verification (run each item at its phase's checkpoint; re-run everything after the final phase)

1. **[Every phase]** `xcodegen generate` succeeds and `xcodebuild test` passes on an iPhone simulator, including that phase's new tests (file protection, tombstone merge, CSV injection, settings clamping, temp-file cleanup, ID keychain migration).
2. Manual flows on simulator/device:
   - **[Phase 1]** Fresh install → set worker info incl. ID → relaunch → data intact; inspect the app container: `workplace_settings.json` contains no plaintext ID; files carry the expected protection attribute.
   - **[Phase 1]** Export PDF/TXT/DOCX/MD → share sheet works → after dismissal/relaunch the temp exports directory is empty.
   - **[Phase 1]** "Delete All My Data" → sessions/settings/log/Keychain/temp files all gone; notifications cleared; (CloudKit build) records deleted.
   - **[Phase 2]** Arrival reminders: enable → staged permission prompts appear → geofence entry fires a notification **without** the `location` background mode; denial states render correctly.
   - **[Phase 4]** Copy a shift row → pasteboard item is local-only and expires.
   - **[Phase 4]** Import a >50 MB file and a 200-page PDF → clean localized error / bounded processing, no hang.
   - **[Phase 5]** App Lock enabled → lock on launch and on return from background; privacy overlay covers content in the app switcher regardless.
3. Grep gates — **[Phase 4]** no `privacy: .public` on identifiers/errors; no coordinates in any `ActivityLogStore.log` call; **[Phase 6]** no raw `Data.write` outside the protected-write helper (SwiftLint rule enforces it).
4. **[Phase 3, re-check at the end]** Re-read `PrivacyInfo.xcprivacy`, `docs/PRIVACY.md`, and the in-app policy strings side by side — they must all describe identical behavior.

Deliver the work as a series of small, logically separated commits (one area per commit), each with tests, so the diff is reviewable — and remember the execution protocol: stop after every phase, post the phase report, and wait for "continue".
