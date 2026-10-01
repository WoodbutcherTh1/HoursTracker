# HoursTracker — Data Inventory

Definition-of-done for privacy changes: if a PR stores, logs, exports, or transmits new user data, update this file, `PrivacyInfo.xcprivacy`, and `docs/PRIVACY.md`.

**Protection class (files):** `.completeFileProtectionUnlessOpen` via `ProtectedFileWriter` unless noted.  
**Delete path:** `AppViewModel.deleteAllUserData()` unless noted.

## Identity & workplace settings (`workplace_settings.json` + Keychain)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| `workerIDNumber` (national ID) | **Keychain** only (empty in JSON/CloudKit) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Until delete / empty save | Keychain delete via settings reset |
| `geminiAPIKey`, `secondaryAPIKey` (Smart Scanner cloud + Assistant) | **Keychain** only, user-supplied | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Until delete / empty save | Keychain delete via Settings |
| `workerFullName` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `employeeNumber` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `workplaceName`, `contractorName` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `locationLatitude` / `locationLongitude` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `locationRadiusMeters` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| Pay rates, OT caps, breaks, currency | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| Marital status, children, spouse employed | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `payrollStartDay`, `restDayWeekday`, `arrivalRemindersEnabled` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `modifiedAt` | Documents JSON; CloudKit if sync on | File protection | Until delete | Local + cloud purge |
| `additionalWorkplaces` (extra jobs: id, color, full settings with an empty national ID) | Documents JSON; CloudKit / account backup with the settings | File protection | Until delete | Local + cloud purge; removing one moves its shifts to Recently deleted |
| `leaveDays` (vacation / recuperation day marks: id, day, kind) — display only, never a pay input | Documents JSON; CloudKit / account backup with the settings | File protection | Until delete | Local + cloud purge |

## Work history (`work_sessions.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Session id, dates, clock in/out, break, day type, night flag, notes, `modifiedAt`, import flags, optional `workplaceID` (extra workplace; absent = main) | Documents JSON; one CloudKit record per session if sync on | File protection | Until delete | Local + cloud purge |
| Corrupt decode sidecar | `work_sessions.json.corrupt*` | Same directory | Until delete-all or manual | `wipeQuarantinedSidecars` |

## Recently deleted & automatic backups (Application Support/HoursTracker)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Deleted shifts + deletion time (`deleted_sessions.json`) | Application Support JSON (not CloudKit, not Files app) | File protection (`ProtectedFileWriter`) | 30 days, then dropped | Restore / "Delete forever" / delete-all |
| Daily full backup of settings + sessions (`Backups/backup-YYYY-MM-DD.json`, full-export JSON format, no activity log) | Application Support JSON (not CloudKit, not Files app); included in the device's own iCloud/Finder backup | File protection (`ProtectedFileWriter`) | Newest 14 days | Delete-all |
| Pre-restore snapshot (`Backups/pre-restore-<unix>.json`) | Same as above | File protection | Newest 3 | Delete-all |

**Account deletion:** Account → Delete account calls the `delete-account` Edge Function (session token only), which deletes the user's `devices` rows and the auth user; `profiles` and `user_backups` cascade. Local data on the iPhone is kept.

When signed in to an account, the account backup (`user_backups`) is also refreshed automatically ~10 s after a change — only when the account holds no shift missing on this device.

## Workplaces (`workplaces.json`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Workplace id, name, hourly rate, currency code, `modifiedAt` | Documents JSON | File protection | Until delete | **Not yet wired into `deleteAllUserData()`** — file exists but nothing reads/writes it yet; must be added when the multi-workplace feature is wired into the UI |

**Note:** storage-only for now (`PersistenceManager.loadWorkplaces()`/`saveWorkplaces()`); not yet part of `PersistableStore`/`SyncingStore`, so it's local-only and not synced to CloudKit until a follow-up PR wires it in.

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
| `smartScannerCloudEnabled` | User opt-in for cloud LLM document extraction **and** the cloud Assistant (default off) | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |
| `assistantButtonEnabled`, `assistantButtonStyle` | Assistant nav-bar button visibility + icon choice | Standard UserDefaults | Until reset | Not wiped today (preference only; no PII) |

| `legal.acceptedVersion`, `legal.acceptedAt` | Which Terms of Use / Privacy Policy version the user agreed to, and when (consent record) | Standard UserDefaults | Until reset | Not wiped by delete-all (the user must agree again only when the version changes) |
| `exportIncludeNotes` | Export → Attach notes toggle | Standard UserDefaults | Until reset | Not wiped (preference only) |

Privacy manifest reason: `CA92.1` (see `PrivacyInfo.xcprivacy`).

## Payslip library (`payslips/` — `PayslipStore`)

| Field | Storage | Protection | Retention | Deleted by |
|---|---|---|---|---|
| Uploaded payslip file (image/PDF) | `payslips/files/` under app container | File protection | Until delete | `AppViewModel.deleteAllUserData()` (verify payslip wipe is wired in) |
| Extracted fields (gross/net pay, employer/employee name, dates, hours) | `payslips/index.json` | File protection | Until delete | Same |
| `PayslipExtraction.rawJSON`, `providerName` | Same index file | File protection | Until delete | Same |

**Note:** if the app-groups entitlement is absent (personal-team builds), `PayslipStore` falls back to the app's own Documents directory rather than a shared container — confirm this is the intended behavior before relying on any future widget/extension sharing this data.

## Third-party transmission — cloud AI features (opt-in, default off)

| What | Sent to | Trigger | Contains |
|---|---|---|---|
| OCR'd timesheet/payslip text (never image/PDF bytes) | Google Gemini API, or an OpenAI-compatible endpoint (e.g. Groq) chosen by the user | Only when `smartScannerCloudEnabled` is on **and** the user supplied an API key | Employer name, employee name, pay figures, dates, hours as recognized from the document |
| Assistant question text (≤500 chars) + today's date/weekday | Same provider / key as above | Only when `smartScannerCloudEnabled` is on **and** a key is saved **and** the user sends a question (`AssistantLLMRouter`) | Whatever the user types. Never their sessions, pay, name, employer, or payslips — the model only returns the name of a report to run; all figures are computed on-device |

These are the only outbound network traffic in the app besides CloudKit. Conversation history is in-memory only (not persisted, not synced, cleared on sheet close). See `docs/PRIVACY_MANIFEST.md` and `docs/ARCHITECTURE.md` ("Networking gate") for the reasoning and the exception to the no-general-networking rule.

## Device registration & announcements (Supabase `devices`, Phase 6)

| Field | Where | Linked to account | Retention | Deleted by |
|---|---|---|---|---|
| Random install id (`announcements.installID`, UserDefaults) | Device + `devices.id` | Only when signed in (`user_id` from the verified session, never the request body) | Until delete-all | `AnnouncementCenter.forget()` on delete-all (row deleted server-side) |
| APNs push token | Device + `devices.apns_token` | Same | Cleared when APNs reports it invalid | Same |
| In-app language, app/build/iOS version, has Watch, has widget, announcements on/off, on a shift now (yes/no only) | `devices` | Same | Updated on each registration | Same |
| Which announcements were shown | `announcement_targets.seen_at` | Via device | Cascades with device / announcement | Same |

Never sent: shift times, pay, name, ID number, employer, location. Tables are RLS-locked with no policies; only the `register-device` and `admin-api` Edge Functions (service role) touch them. The admin dashboard gets aggregate counts only (`admin_stats()`); "selected users" targeting resolves emails server-side and returns only a count plus unknown emails. CI / test runs never register (`AnnouncementCenter.isAutomatedRun`).

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

No analytics, advertising IDs or crash reporters. The only developer-operated server is the Supabase project (account backup, feedback relay, and the announcement device registry above). (The opt-in cloud AI features — Smart Scanner extraction and the Assistant — send text to a third-party AI provider the user configures, see the section above, and are separate from HoursTracker's own server.) See `PrivacyInfo.xcprivacy` and `docs/PRIVACY_MANIFEST.md`.
