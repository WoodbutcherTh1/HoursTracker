# HoursTracker — Security Hardening Summary

**Date:** 16 July 2026  
**Scope:** App Store–ready enterprise hardening for an offline-first SwiftUI app (iOS 17+, Apple frameworks only).  
**Evidence log:** `docs/HARDENING_LOG.md` (phases 1–6)  
**Final automated verification:** `swiftlint lint --strict` (0 violations); **146** XCTest cases, 0 failures (`iPhone 16, iOS 18.3.1`).

---

## Finding → fix → evidence

| ID | Finding | Fix | Verification evidence |
|---|---|---|---|
| **A1** | Documents JSON / exports written without Data Protection | `ProtectedFileWriter` (atomic + `.completeFileProtectionUnlessOpen`); launch migration | `ProtectedFileWriterTests`; SwiftLint `no_raw_data_write` |
| **A2** | National ID in plaintext JSON + CloudKit | Keychain `WhenUnlockedThisDeviceOnly`; empty in JSON/CloudKit; migrate on load | `WorkerIDKeychainPersistenceTests`; `SyncMergeTests` |
| **A3** | GPS coordinates logged in activity log | Removed from `applyLocation`; scrub legacy location details | `ActivityLogStoreTests`; call-site audit |
| **A4** | Export temps unprotected, never cleaned | `ExportTempFileStore` under `tmp/Exports/`; wipe on share / launch / background / delete-all | `ExportTempFileStoreTests`; `AppViewModelTests` |
| **A5** | Delete All incomplete (cloud, Keychain, temps, notifications) | Extended `deleteAllUserData` + CloudKit purge + partial-failure UX | `AppViewModelTests`; `SyncingPersistenceStoreTests` |
| **A6** | `UIBackgroundModes: location` / continuous background location | Removed background location mode & related APIs | `project.yml` / Info.plist; location flow tests |
| **A7** | Location permission UX incomplete | Staged When-In-Use → Always; wait for auth; Settings denial + Open Settings | `LocationPermissionFlowTests` |
| **A8** | CloudKit traffic without explicit user consent | `iCloudSyncEnabled` default **off**; sync/upload/delete no-op until on | `CloudSyncPreferenceTests`; privacy docs |
| **A9** | Deleted sessions could resurrect via CloudKit | Tombstones + LWW conflict handling + serial `CloudWriteQueue` | `SessionTombstoneStoreTests`; `SyncMergeTests` |
| **A10** | Privacy declarations incomplete / inconsistent | `PrivacyInfo.xcprivacy` (not collected + `CA92.1`); policy/docs/branding aligned | Manifest + `docs/PRIVACY.md` / `PRIVACY_MANIFEST.md` side-by-side review |
| **A11** | CSV / XML / Markdown injection in exports | `ExportSanitizer` | `ExportSanitizerTests` |
| **A12** | Unbounded / extension-trusting imports; Zip bounds | Size/UTType/PDF page caps; ZipWriter bounds checks | `TimesheetScannerBoundsTests`; `ZipWriterBoundsTests` |
| **A13** | Unlocked UI / switcher / plain ID field | Optional App Lock + privacy overlay + masked ID | `AppLockTests` |
| **A14** | Pasteboard syncs indefinitely via Handoff | `localOnly` + 60s expiry | History copy path review (Phase 4) |
| **A15** | Logger `.public` on identifiers/errors | `.private` only; CI rule | Grep + SwiftLint `no_logger_privacy_public` |
| **A16** | Weak numeric / ID validation on settings | Clamp on init/decode; soft Israeli ID checksum warning | `WorkplaceSettingsValidationTests` |
| **A17** | Mutable Actions tags; broad token; no lint/secrets | SHA-pinned Actions; `contents: read`; SwiftLint; gitleaks; `SECURITY.md` | `.github/workflows/ci.yml`; local SwiftLint clean |
| **B1** | Raw file writes possible outside helper | Single write helper + lint gate | SwiftLint; only `ProtectedFileWriter` uses `.write(to:)` in app sources |
| **B2** | No field-level inventory | `docs/DATA_INVENTORY.md` | Doc present; PR template requires updates |
| **B3** | No privacy PR gate | `.github/pull_request_template.md` | Template checked into repo |
| **B4** | Activity log could grow PII | Non-PII details rule in code + docs | `ActivityLogStore` comment; inventory / ARCHITECTURE |
| **B5** | Corrupt JSON silently became empty | Quarantine to `.corrupt` sibling; delete-all wipes sidecars | `CorruptFileQuarantineTests` |
| **B6** | No release security checklist | `docs/RELEASE_CHECKLIST.md` | Checklist present |
| **B7** | Networking could land without gates | Documented ATS / pinning / privacy gate in ARCHITECTURE | `docs/ARCHITECTURE.md` “Networking gate” |

---

## Residual risks & accepted trade-offs

| Risk / trade-off | Why accepted |
|---|---|
| **Unlocked authenticated process** can read plaintext in memory | Domain layer must enumerate full data through existing store APIs; protection is at-rest only |
| **Device thief with unlocked phone** (App Lock off) | App Lock is opt-in (default off) to avoid surprising UX; privacy overlay still covers app switcher |
| **National ID does not sync across devices** | Keychain `ThisDeviceOnly` — intentional so ID never enters CloudKit |
| **Simulator Data Protection attributes unreliable** | Options seam unit-tested; **device** container inspection required before submission |
| **User-exported reports** contain name/ID/pay by design | Sanitized against formula/markup injection; sharing is the user’s choice |
| **UserDefaults prefs** (`iCloudSyncEnabled`, `appLockEnabled`) not wiped by Delete All | Non-PII preferences only; documented in inventory |
| **Gitleaks CI license** on private orgs | CI-only tool; ops concern for the repo owner if license required |
| **Apple platform / CloudKit account compromise** | Mitigated by opt-in sync + private DB + no national ID upload; Apple account security is out of app control |
| **OCR import of hostile PDFs** beyond unit bounds | Size/page caps enforced; large-file UX remains a manual device check |

---

## Manual App Store / device steps (submitter owns these)

Complete before App Store Connect submission (also mirrored in `docs/RELEASE_CHECKLIST.md`):

1. **App Privacy questionnaire** — Answer to match `HoursTracker/Resources/PrivacyInfo.xcprivacy` and `docs/PRIVACY.md`:
   - Tracking: **No**
   - Data collected by the developer: **None** (on-device / user-controlled iCloud only; not “collected” by you)
   - Declare location / camera / photos usage consistent with purpose strings if Connect UI asks for linked purposes
2. **Host privacy policy** at a public HTTPS URL; paste into App Store Connect. Keep URL content aligned with in-app `PrivacyPolicyView` / `docs/PRIVACY.md`.
3. **Encryption export compliance** — Keep `ITSAppUsesNonExemptEncryption` **false** only while using exempt/OS crypto (Keychain, Data Protection, LocalAuthentication). Revisit if custom CryptoKit schemes are added later.
4. **Physical device verification**
   - Confirm Documents JSON / export temps report `NSFileProtectionCompleteUnlessOpen` (or equivalent)
   - Confirm `workplace_settings.json` has empty `workerIDNumber` and ID lives in Keychain
   - Exercise App Lock, arrival-reminder permission staging, export share cleanup, Delete All My Data (and CloudKit purge on a CloudKit-enabled build)
5. **CloudKit shipping build** (if offering sync) — Copy entitlements from `docs/HoursTracker.entitlements.cloudkit.example`, set `HTCloudKitEnabled`, provision `iCloud.com.hourstracker.app`; confirm sync toggle defaults **off**.
6. **Permission copy review** — Re-read all usage descriptions (location, camera, photos, Face ID, notifications) in `project.yml` / localized Info.plist strings.
7. **CI on `main`** — Confirm GitHub Actions (tests + SwiftLint + gitleaks) green on the release commit.

---

## Quick reference — where to look

| Topic | Doc / code |
|---|---|
| Phase-by-phase detail | `docs/HARDENING_LOG.md` |
| Field inventory | `docs/DATA_INVENTORY.md` |
| Threat model | `docs/THREAT_MODEL.md` |
| Vulnerability reports | `SECURITY.md` |
| Architecture / networking gate | `docs/ARCHITECTURE.md` |
| Release checklist | `docs/RELEASE_CHECKLIST.md` |
| User privacy policy | `docs/PRIVACY.md` |
| Privacy manifest notes | `docs/PRIVACY_MANIFEST.md` |
