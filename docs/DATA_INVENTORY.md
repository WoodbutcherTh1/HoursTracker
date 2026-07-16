# HoursTracker — Data Inventory

Definition-of-done for privacy changes: if a PR stores, logs, exports, or transmits new user data, update this file, `PrivacyInfo.xcprivacy`, and `docs/PRIVACY.md`.

**Protection class (files):** `.completeFileProtectionUnlessOpen` via `ProtectedFileWriter` unless noted.  
**Delete path:** `AppViewModel.deleteAllUserData()` unless noted.

## Identity & workplace settings (`workplace_settings.json` + Keychain)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| `workerIDNumber` (national ID) | **Keychain** only (empty in JSON/CloudKit) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Until delete / empty save | Keychain delete via settings reset |
| `workerFullName` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `employeeNumber` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `workplaceName`, `contractorName` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `locationLatitude` / `locationLongitude` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `locationRadiusMeters` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| Pay rates, OT caps, breaks, currency | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| Marital status, children, spouse employed | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `payrollStartDay`, `restDayWeekday`, `arrivalRemindersEnabled` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `modifiedAt` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |

## Work history (`work_sessions.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Session id, dates, clock in/out, break, day type, night flag, notes, `modifiedAt`, import flags | Documents JSON; one CloudKit record per session if sync on | File protection | Until delete | Local + cloud purge |
| Corrupt decode sidecar | `work_sessions.json.corrupt*` | Same directory | Until delete-all or manual | `wipeQuarantinedSidecars` |

## Activity log (`activity_log.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Event message, level, category, timestamp, optional **non-PII** details | Documents JSON (not CloudKit) | File protection | Cap ~500 entries; until wipe | `wipeForPrivacy` / delete-all |

**Rule:** details may contain event names, counts, durations, and format identifiers only — **never** PII, GPS coordinates, or free-text notes.

## Sync control & App Lock (UserDefaults)

| Key | Purpose | Protection | Retention | Deleted by |
|---|---|---|---|---|
| `iCloudSyncEnabled` | User opt-in for CloudKit (default off) | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |
| `appLockEnabled` | Optional biometric App Lock (default off) | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |

Privacy manifest reason: `CA92.1` (see `PrivacyInfo.xcprivacy`).

## Tombstones (`session_tombstones.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Deleted session UUID + `deletedAt` | Documents JSON | File protection | Pruned after 90 days; until delete-all | `removeAll` + sidecar wipe |

## Export temps (`tmp/Exports/`)

| Content | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| PDF/TXT/DOCX/MD/CSV reports (may include name, ID, pay) | App tmp `Exports/` | File protection on write | Ephemeral | Share completion, launch, background, delete-all |

## Local notifications

| Content | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Reminder titles/bodies (no national ID) | Notification center | OS-managed | Until fired / cancelled | `removeAllPending` / `removeAllDelivered` on delete-all |

## CloudKit private database (opt-in only)

| Record | Payload | National ID | Deleted by |
|---|---|---|---|---|
| `WorkSession` | JSON session blob + `modifiedAt` | Never | `purgeUserCloudData` / per-session delete |
| `workplace-settings` | Settings JSON with empty `workerIDNumber` | Never | Purge when sync off / delete-all |

## Not collected

No analytics, advertising IDs, crash reporters, or developer-operated servers. See `PrivacyInfo.xcprivacy` and `docs/PRIVACY_MANIFEST.md`.
