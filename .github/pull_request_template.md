## Summary

<!-- What changed and why (1–3 bullets). -->

## Privacy review gate

- [ ] Does this change **store, log, export, or transmit** new user data?
  - If **yes**: update `HoursTracker/Resources/PrivacyInfo.xcprivacy`, `docs/PRIVACY.md` (and in-app policy strings if needed), and `docs/DATA_INVENTORY.md`.
  - If **no**: leave unchecked and note N/A below.

Privacy impact: <!-- N/A or brief description -->

## Security / data handling

- [ ] New file writes go through `ProtectedFileWriter` / `FileWriting` (no raw `Data.write(to:)` in app sources).
- [ ] Activity log details (if any) contain only event names, counts, durations, or format identifiers — never PII, GPS coordinates, or free-text notes.
- [ ] No new networking, analytics, or third-party SDK.

## Test plan

- [ ] `xcodegen generate`
- [ ] `xcodebuild test` (HoursTracker scheme) green
- [ ] Manual checks relevant to this PR (list below)

<!-- Additional verification steps -->
