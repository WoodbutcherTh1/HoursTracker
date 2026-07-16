# HoursTracker — Threat Model

Short model for App Store / enterprise review. Assets and mitigations map to the hardening work in `docs/HARDENING_LOG.md`.

## Assets

| Asset | Sensitivity | Where it lives |
|---|---|---|
| Israeli national ID (teudat zehut) | Critical PII | Keychain (`WhenUnlockedThisDeviceOnly`); in memory on `WorkplaceSettings` |
| Worker full name, employee number | High PII | Documents JSON; optional CloudKit private DB |
| Workplace GPS coordinates | Precise location | Documents JSON; optional CloudKit |
| Marital / family status, pay rates | Sensitive | Documents JSON; optional CloudKit |
| Work session history (times, breaks, pay) | Sensitive | Documents JSON; optional CloudKit; export temps |
| Activity log | Low–medium (must stay free of PII) | Documents JSON |
| Session tombstones | Operational | Documents JSON |

## Adversaries & scenarios

| Adversary | Goal | Mitigations |
|---|---|---|
| **Device thief** (locked phone) | Read Documents after reboot / before unlock | Data Protection `.completeFileProtectionUnlessOpen` via `ProtectedFileWriter`; Keychain accessibility class |
| **Device thief** (unlocked phone) | Browse app UI / switcher | Optional App Lock (LAContext); privacy overlay when `scenePhase != .active`; masked ID in Settings |
| **Shoulder surfer** | See ID / pay on screen | Masked ID; App Lock; no ID in activity log |
| **Malicious import file** | Crash / DoS / injection via OCR import | Size caps, UTType checks, PDF page bound, ZipWriter bounds |
| **Hostile spreadsheet paste** | Formula injection when user opens CSV export | `ExportSanitizer` CSV / XML / Markdown escaping |
| **Cloud account compromise** | Read synced sessions/settings | Sync off by default; private DB only; national ID never uploaded; user can purge; tombstones prevent resurrection of deleted sessions |
| **Accidental share / leftover exports** | PII left in tmp | `ExportTempFileStore` under `tmp/Exports/`, wipe on share complete / launch / background / delete-all |
| **Repo / CI supply-chain** | Inject secrets or mutable Actions | SHA-pinned Actions, `permissions: contents: read`, SwiftLint write gate, gitleaks |

## Out of scope / accepted risk

- Full-disk forensic access to an unlocked, authenticated process (in-memory plaintext is required for the domain layer).
- Apple platform bugs in Keychain, Data Protection, or CloudKit.
- User who exports a report and shares it themselves (export is intentional; sanitization only prevents formula/markup injection).
- Cross-device national ID sync (intentionally device-local Keychain).

## Related docs

- `docs/DATA_INVENTORY.md` — field-level inventory
- `docs/PRIVACY.md` / `PrivacyInfo.xcprivacy` — user-facing declarations
- `SECURITY.md` — vulnerability reporting
