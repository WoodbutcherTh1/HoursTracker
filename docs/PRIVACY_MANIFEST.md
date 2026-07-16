# Privacy manifest reasoning

`HoursTracker/Resources/PrivacyInfo.xcprivacy` must stay aligned with real behavior and with App Store Connect’s App Privacy questionnaire.

## Why “Data Not Collected”

Apple’s “collected” types mean data that is transmitted off the device **to you (the developer)** or to a third party you control for purposes such as analytics, advertising, or your own servers.

HoursTracker today:

- Stores data in the app sandbox (JSON + Keychain) and optional **user-private** CloudKit database
- Has **no** developer backend, analytics, crash reporter, or advertising SDK
- Never sends national ID to iCloud (Keychain, ThisDeviceOnly)

Therefore `NSPrivacyCollectedDataTypes` is an **empty array** and `NSPrivacyTracking` is `false`.

Optional iCloud sync is the user’s Apple ID private database — it is not developer “collection” in the App Privacy sense. If a future feature transmits data to a server you operate, update this manifest **and** the App Privacy questionnaire before shipping.

## Required-reason APIs

| API category | Reason | Why |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `iCloudSyncEnabled` opt-in flag (`CloudSyncPreference`) |

No file-timestamp, disk-space, boot-time, or active-keyboard required-reason APIs are used for tracking. `FileManager.attributesOfItem` is used only for Data Protection class / file size checks in security paths — if App Review ever flags file timestamps, add the matching reason only after confirming the exact API.

## Keep in sync

When changing storage, logging, export, or networking, update:

1. `PrivacyInfo.xcprivacy`
2. `docs/PRIVACY.md` and in-app `PrivacyPolicyView` strings
3. `docs/DATA_INVENTORY.md` (Phase 6)
4. App Store Connect App Privacy answers
