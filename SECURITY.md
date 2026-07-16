# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| Latest App Store / TestFlight build from `main` | Yes |
| Older App Store builds | Best-effort only — upgrade to the latest release |

HoursTracker is a single-app product; security fixes ship in the next App Store release rather than backport branches.

## Reporting a vulnerability

Please report security issues **privately**. Do not open a public GitHub issue for vulnerabilities that could expose user data.

**Contact:** [support@hourstracker.app](mailto:support@hourstracker.app)

Include:

1. A clear description of the issue and impact (e.g. plaintext national ID on disk, CloudKit resurrection, export temp retention).
2. Steps to reproduce, affected iOS version, and build/commit if known.
3. Whether you have a suggested fix (optional).

We aim to acknowledge reports within **7 days** and to provide a remediation timeline once the issue is confirmed. Please give us a reasonable window to ship a fix before any public disclosure.

## Scope notes

- The app is offline-first. The only permitted remote store is the user’s **CloudKit private database**, behind compile-time + user opt-in flags.
- There is no server-side account system operated by the developer; Apple ID / iCloud security is out of scope except for how this app uses CloudKit APIs.
- Issues that require physical access to an unlocked device after the user has authenticated are still welcome (App Lock, file protection, Keychain) but may be accepted as residual device-theft risk — see `docs/THREAT_MODEL.md`.
