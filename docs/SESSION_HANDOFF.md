# Session handoff — 29 Sep 2026

Read this first in a new session. It replaces the long chat history.

## Where things are

- Repo `WoodbutcherTh1/HoursTracker`, branch **`claude/planning-requests-bb6hz1`**, draft **PR #66** (base `main`).
  Push only to this branch; nothing merges to `main` without the owner's approval.
- Version **1.8**, build **26** in `project.yml` (`CURRENT_PROJECT_VERSION`). Every TestFlight upload needs a higher
  build: build 26 is the next upload; after it goes up, the one after must be **27**.
- Latest code commit: `1579354`. The Siri commit compiled but the app wouldn't install: iOS allows at most 3
  `INAlternativeAppNames` and there were 4. `1579354` trims them to 3 (ar/he/ru). CI passed on it, and on the build-26 bump (`09ac54a`). Build 26 is ready to Archive once the owner says to upload.

## How to work with the owner (must keep)

- The owner writes Arabic (sometimes Hebrew). **Every reply goes inside a ```text block, in simple Arabic.** Keep it short
  and concrete; the owner is not technical.
- **Don't change anything without explicit approval.** Propose → wait for "نعم/موافق/اعمله" → implement.
- Don't touch the logic of PersistenceManager, SyncLogic, pay math (OvertimeCalculator), Auth, or Scanner OCR.
- No new libraries. One commit per change. No model identifiers in commits. Commit trailers:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and the session link line.
- Secrets: never ask for or accept `.p8`, the Gmail app password, or API keys in chat. The OpenRouter key goes into
  Supabase → Edge Functions → Secrets as `OPENROUTER_API_KEY`; the owner just replies "done".
- Don't delete the owner's images/drafts (`marketing/app-store/drafts`, `screenshots`).
- Never skip, disable or quarantine a test; no empty commits to kick CI.
- Rest days change pay premium; never bind WeekPattern to them.

## CI and visual checks

- CI (`.github/workflows/ci.yml`): gitleaks, SwiftLint strict, `xcodebuild test` on macos-26 (Xcode 26 SDK, iOS 17
  deployment target). There's no local Swift toolchain, so CI is the compiler.
- **Design QA** runs only when the HEAD commit message contains `[design-qa]` (or via workflow_dispatch). It runs 9 setups
  (SE / 15 Pro, he/ar/en, XL text, Reduce Motion, new user, rate 0, night). Screenshots are embedded in the job log
  between `=== QA-IMG name ===` and `=== QA-END ===`. Decode them with a small base64 script (the scratchpad `decode_qa.py`
  from the old session is gone; rewrite it: split the log lines, strip the timestamp, base64-join the lines between the markers).
- App Store screenshots workflow: tag `[screenshots]`.
- Known flaky UI tests (a re-run or the next commit passes): `DaySummarySwipeUITests` ("Clock Out never appeared")
  and a simulator "Timed out while requesting screenshot". `ScreenshotTests` relaunch was fixed in `c40cf5d`.

## Done in the last session (all pushed)

1. **BUG #1**: rate field digits invisible in he/ar. Fixed with `AmountField` (drawn digits over a clear TextField).
2. **Russian**: 4th app language (899 catalog strings, InfoPlist, widget, Live Activity, Watch, export report,
   user guide, notifications). Admin announcements still go to Russian users in English (server supports en/he/ar).
3. **Home Part 3**:
   - Pinned Clock In/Out door plus the break button on short screens, with an opaque backing.
   - No lone 00:00 in the week chart.
   - Hourly-rate card for new users or a missing rate.
   - Six-month trend card with an empty state.
   - Night-shift moon label ("started yesterday").
   - One-time Lock Screen tip.
   - Haptics on the secondary buttons.
4. **Lock Screen (Live Activity) fix**:
   - Ends immediately on clock-out, and every activity is ended.
   - The banner is replaced when the open shift's start time is edited.
   - Leftovers are cleaned when there is no open shift.
5. **Shift summary notification**: local, only when clocking out outside the app. Tapping it opens the Day Summary. It has a
   toggle in Settings → Notifications.
6. **Settings unsaved changes**:
   - The Save button is quiet or accent-filled with a dot.
   - Leaving the tab asks Save / Discard / Keep editing.
   - A 60 s background reminder (with a Discard action).
   - Edits are no longer silently reset.
7. **Gross | Net switch**: Liquid Glass with a sliding thumb (`glassEffect` on iOS 26, material fallback).
8. **Siri & Shortcuts** (`HoursTracker/Intents/`):
   - Start/End shift and Start/End break.
   - Shift status, and Hours & Earnings (today/week/month/last month).
   - Export Report (PDF/CSV file) and Ask HoursTracker (the assistant by voice).
   - Phrases in en/he/ar/ru (`Resources/AppShortcuts.xcstrings`) and `INAlternativeAppNames`.
   - A Control Center toggle (iOS 18, `ShiftControl` in the widget), plus SiriReport unit tests.
9. App Store marketing images for en/he/ar are done in `marketing/app-store/final`.

## Waiting / next

- [ ] **CI on the Siri commits** → fix if red → bump build to **26** → tell the owner to Archive and upload. Then give the owner a
      short TestFlight test list:
  - Siri phrases in Arabic, Hebrew and English.
  - The Action Button and the Control Center toggle.
  - Clock out from the Lock Screen: the banner disappears and the summary notification arrives.
  - Settings Save and the leave-tab prompt.
  - The glass Gross/Net switch.
- [ ] Owner approval of Home Part 3 visuals (photos were sent; no explicit "موافق" yet).
- [ ] Later (owner said "not now"):
  - Russian App Store screenshots and description.
  - Admin messages in Russian (needs a Supabase change).
- [ ] Next version: AI assistant **option B**, an OpenRouter key server-side (Supabase Edge Function) with a daily per-user
      limit. It waits for the owner to add `OPENROUTER_API_KEY`. Siri's "Ask HoursTracker" improves automatically with it.
- The owner said they have more ideas; ask for them.
