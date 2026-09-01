# CKSyncEngine Migration — Feasibility Assessment

**Status:** Assessed — not migrated (see recommendation below).

## What we have today

`iCloudSyncManager` implements hand-rolled CloudKit sync:

- Pull: `fetchChanges` / `CKFetchRecordZoneChangesOperation`, delta tokens persisted.
- Push: `CKModifyRecordsOperation` on every save (last-write-wins per record).
- Conflict handling: local records win on `CKError.serverRecordChanged`.
- Triggers: explicit `syncNow()` on launch/app-active, plus after mutations.

The core loop is correct and has passed hardening review, but it is
**polling-based and single-process**: changes made on another device are only
seen when the app foregrounds, and there is no automatic merging of edits made
while offline.

## What CKSyncEngine gives us

- **Push-based sync**: `CKDatabase` change notifications wake the app when
  another device writes, so edits appear without the user reopening the app.
- **Automatic merge/conflict handling**: `CKSyncEngine` tracks record states,
  serializes operations, and handles the retry/token bookkeeping that
  `fetchChanges` requires us to hand-roll.
- **Delta-based record state**: `stateVector`-style merging reduces
  last-write-wins data loss for independent edits on the same day.

## Cost / risk of migrating

| Item | Effort | Notes |
| --- | --- | --- |
| Rewrite of `iCloudSyncManager` | Medium | Same CloudKit schema; only the transport changes. |
| Record-state reconciliation | Medium | Need a migration path for records already created with `CKRecord.ID` + `recordChangeTag` used by the hand-rolled loop (`CKRecord` IDs are compatible; `CKSyncEngine` re-reads the zone). |
| **Paid team / entitlements** | **Blocker today** | CloudKit push notifications (`remote-notification` background mode + `aps-environment`) require a paid Apple Developer Program membership. The repo's docs already note the project runs on a personal-team / free configuration, which is why sync currently polls on foreground instead of waking in background. |
| Testing | High | Real two-device conflict scenarios need macOS CI + physical devices. |

## Recommendation

**Defer the migration until the team entitlement is available.** The
architectural direction (keep `iCloudSyncManager` as the single sync façade and
swap its transport to `CKSyncEngine` behind it) is sound, but the headline
benefit — background push delivery — is disabled by the entitlement
constraint, leaving us paying the migration cost for a foreground-only win.

### Interim improvements (no entitlement needed)

1. **Faster convergence while running**: trigger `syncNow()` after
   scene-phase → `.active` (already done) and debounce mutations instead of
   syncing on every save.
2. **Same-device conflict safety**: keep last-write-wins but stamp records
   with `modifiedAt` and prefer the newer timestamp on `serverRecordChanged`
   rather than always trusting the local copy (today automatic clock-in wins
   even if the server copy is newer).
3. **Sync diagnostics UI**: surface the last `syncState`/error in the
   existing Settings sync section so stuck zones are visible to the user
   instead of silent.

When the entitlement lands, ship points 1–3 first, then migrate the transport
in a single PR that keeps the `iCloudSyncManager` API stable.