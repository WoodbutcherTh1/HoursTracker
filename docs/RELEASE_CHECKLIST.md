# HoursTracker — Release Checklist

Run before every App Store / TestFlight submission.

## Privacy & App Store Connect

- [ ] **App Privacy questionnaire** answers match `HoursTracker/Resources/PrivacyInfo.xcprivacy` and `docs/PRIVACY.md` (data not collected by the developer; iCloud only if user opts in; location for geofence/arrival; no tracking).
- [ ] Host the privacy policy at a **public URL** and set it in App Store Connect (in-app copy in `PrivacyPolicyView` / `docs/PRIVACY.md` must stay aligned).
- [ ] `ITSAppUsesNonExemptEncryption` remains **false** only while using exempt / OS-provided crypto (Keychain, Data Protection, LocalAuthentication — no custom non-exempt crypto).
- [ ] Re-review all **permission usage strings** (`NSLocation*`, `NSCamera*`, `NSPhotoLibrary*`, `NSFaceIDUsageDescription`, notifications) in `project.yml` / Info.plist / `InfoPlist.xcstrings`.

## Data protection (device build)

- [ ] Install a **physical-device** build; confirm Documents JSON and export temps use Data Protection (container inspection / `NSFileProtectionCompleteUnlessOpen`). Simulator attributes are unreliable.
- [ ] Confirm national ID is **absent** from `workplace_settings.json` and present only in Keychain.
- [ ] Confirm CloudKit builds (if shipping with sync): entitlements from `docs/HoursTracker.entitlements.cloudkit.example`, `HTCloudKitEnabled`, sync toggle default **off**.

## Functional security smoke

- [ ] Export → share → dismiss; `tmp/Exports/` empty after completion or relaunch.
- [ ] Delete All My Data clears sessions, settings, activity log, Keychain ID, export temps, notifications, tombstones/quarantine sidecars; CloudKit purge when supported.
- [ ] Arrival reminders: staged When-In-Use → Always; no `UIBackgroundModes: location`.
- [ ] App Lock (if testing): lock on launch and after ~30s background; privacy overlay in app switcher regardless.
- [ ] Pasteboard copy from History is local-only with short expiry.

## CI / supply chain

- [ ] `main` CI green: secret scan, SwiftLint (strict custom rules), unit tests.
- [ ] No new third-party app dependencies; Actions remain **SHA-pinned**.

## Full Part D verification

Re-run the manual items in the hardening brief / `docs/HARDENING_LOG.md` Part D notes for the release candidate.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Engineer | | |
| Privacy reviewer | | |
