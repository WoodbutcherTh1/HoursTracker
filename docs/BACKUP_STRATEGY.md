# Backup strategy (HoursTracker)

## Why this exists

On 2026-07-19 a real-device install after App Group entitlement changes wiped the sandbox
(see `docs/DATA_LOSS_INCIDENT_2026-07-19.md`). History and settings lived only in Documents
JSON with no rolling backup.

## Format

- ID: `hourstracker.backup` · version `1` · extension `.htbackup.json`
- Contents: all sessions, full `WorkplaceSettings` (name, ID, contractor, tax credit inputs,
  rates, OT, language prefs), activity log

## Layers

| Layer | Trigger | Location | Retention |
|-------|---------|----------|-----------|
| Manual export | Settings → Backup | Share / Files | User-owned |
| Sync Now | Settings | App Group `backups/` (Documents fallback) | Rolling 14 |
| Automatic | Launch if >20h; after clock-out | Same | Last **14** |
| Pre-restore | Before Replace import | `pre-restore-*.htbackup.json` | Counts toward 14 |

## Before changing entitlements / signing

1. **Export full backup** from Settings (save off-device).
2. Optionally Download Container from Xcode.
3. Then change App Groups / provisioning / rebuild.
