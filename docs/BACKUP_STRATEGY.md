# Backup strategy (HoursTracker)

## Why this exists

On 2026-07-19 a real-device install after App Group entitlement changes wiped the sandbox (see `docs/DATA_LOSS_INCIDENT_2026-07-19.md`). History and settings lived only in Documents JSON with no rolling backup.

## What is backed up (lossless)

Format ID: `hourstracker.backup` · version `1` · file extension `.htbackup.json`

Contents:

- All `WorkSession` rows (open + closed)
- Full `WorkplaceSettings` including worker ID (present in the export payload; re-written to Keychain on restore)
- Activity log entries
- Metadata: exportedAt, appVersion, sessionCount, monthCount, lastSessionClockIn

**Not** a substitute for payroll PDF/CSV — those remain under Export / Full Data Export.

## Layers

| Layer | Trigger | Location | Retention |
|-------|---------|----------|-----------|
| Manual export | Settings → Backup → Export | User picks Files / Share | User-owned |
| Sync Now | Settings button | App Group `backups/latest.htbackup.json` + dated copy | Rolling 14 |
| Automatic | Daily on launch if >20h since last; also after each successful clock-out | App Group `backups/` | Last **14** files |
| Pre-restore | Immediately before Replace import | App Group `backups/pre-restore-*.htbackup.json` | Counts toward rolling 14 |

## Rules before changing signing / entitlements

1. On any device with real data: **Settings → Export full backup** (save to Files / AirDrop).
2. Optionally: Xcode → Download Container.
3. Only then change App Groups, bundle IDs, or team / provisioning.
4. After Run: confirm History count and Settings name/ID still match.

Never rely on “update in place” when entitlements change — treat it as a possible clean install.

## Restore modes

- **Replace:** wipe current sessions/settings/log, write backup (after auto pre-restore snapshot).
- **Merge:** union sessions by `id` (backup wins on conflict); settings from backup; log merged by `id`.
