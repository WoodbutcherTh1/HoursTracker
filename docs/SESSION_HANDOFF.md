# Session handoff — 9 Nov 2026

Read this first in a new session. It replaces the long chat history. For
architecture, file routing, and known-bug history, see `MASTER_MAP.md` —
that's the from-the-repo reference; this file is the point-in-time status.

## Where things are

- Repo `WoodbutcherTh1/HoursTracker`, working directly on **`main`** (this
  session merged the prior working branch `claude/planning-requests-bb6hz1`
  into `main` and has pushed directly to it since, with the owner's explicit
  authorization each time).
- Version **1.11**, build **30** in `project.yml` (`CURRENT_PROJECT_VERSION`).
- **Deadline: App Store update must submit by Thursday.** This week is
  submission-blockers-and-polish only — no new features, and the
  `CKSyncEngine` migration is explicitly deferred past this week (see
  `docs/ROADMAP.md`), even though it's no longer blocked on account tier.
- All 484 unit tests passing as of the last commit on `main`.

## How to work with the owner (must keep)

- The owner communicates in English and is technical — reads diffs, git
  log, and build output directly. (An earlier version of this file said the
  owner writes Arabic and isn't technical, and required Arabic-only replies
  with no unapproved changes — that no longer matches how this project is
  actually run; don't resurrect it.)
- The owner grants explicit scoped autonomy per session (e.g. "execute in
  order, don't stop for approval unless you hit a real blocker") — that
  authorization is for the stated scope and session, not a standing rule to
  push to `main` unprompted in a future session. Default back to confirming
  before anything that pushes to `main`, touches signing/entitlements, or
  changes backend security posture, unless the current session has said
  otherwise.
- Don't touch the logic of `PersistenceManager`, sync, pay math
  (`OvertimeCalculator`), Auth, or Scanner OCR without a clear reason tied to
  the task at hand — these are the highest blast-radius files in the app.
- No new third-party libraries without asking — `supabase-swift` is
  deliberately the only one.
- One commit per logical change, with an accurate message (see git log for
  the house style — recent commits describe *why*, not just *what*).
- **Secrets: never ask for or accept the `.p8` key file, API keys, or any
  credential contents in chat.** Give the owner the exact CLI/dashboard
  steps to set them themselves (e.g. `supabase secrets set ...`); the owner
  just confirms it's done.
- Don't delete the owner's images/drafts (`marketing/`, `design-qa/` —
  the latter is explicitly "leave alone" per `MASTER_MAP.md`'s file tree).
- Never skip, disable, or quarantine a test; no empty commits to kick CI.
- Rest days change the pay premium; never bind `WeekPattern` to them.
- After editing `Localizable.xcstrings`, check
  `HoursTrackerWatch/Resources/Localizable.xcstrings` is still a symlink
  (`readlink` it) — Xcode's build system has intermittently materialized it
  into a real file on this machine (not reliably reproducible; a
  `postbuildScripts` phase in `project.yml` now self-heals it every build,
  but verify after anything unusual).

## CI and visual checks

- CI (`.github/workflows/ci.yml`): gitleaks, SwiftLint strict, `xcodebuild
  test` on macos-26 (Xcode 26 SDK, iOS 17 deployment target). There's no
  local Swift toolchain in some environments, so CI is the compiler of
  record there — but this session had a full local Xcode toolchain and
  verified every change with real `xcodebuild`/`xcodebuild test` runs.
- **Design QA** runs only when the HEAD commit message contains
  `[design-qa]` (or via `workflow_dispatch`).
- App Store screenshots workflow: tag `[screenshots]`.

## Done recently (this session, 8–9 Nov, all pushed to `main`)

1. **Google Sign-In**: Supabase-hosted OAuth, no Google SDK. Published to
   Production (non-sensitive scopes, no Google review needed). Tested live.
2. **Apple Sign-In**: native `ASAuthorizationController` flow. Paid Apple
   Developer account confirmed and entitlement enabled. Tested live.
3. **Apple account-deletion token revocation** (App Store Review Guideline
   5.1.1(v)): a new `apple-token-exchange` Edge Function stores a refresh
   token right after native Apple sign-in (the authorization code it's
   exchanged from is one-time-use and expires in minutes — unusable by the
   time an account is actually deleted); `delete-account` reads it and calls
   Apple's `/auth/revoke` before removing the account. See
   `docs/SOCIAL_SIGN_IN.md`.
4. Hosted privacy policy (`docs/privacy-policy.html`) live on GitHub Pages.
5. Export freeze fix, Settings "jump" fix, Live Activity/widget pay-number
   sync fix, three backend security hardenings (`ai-assist`, `support-chat`,
   `submit-feedback`), Humanizer copy pass + synced translations across all
   5 languages, and a self-healing build-phase fix for the Watch catalog
   symlink. Full detail in `git log` and `MASTER_MAP.md` §4.

## Waiting / next

- [ ] **This week (submission blockers only, due Thursday)**: whatever App
      Review flags beyond what's already fixed. Check back against App Store
      Review Guideline 5.1.1(v) (done), 2.1 (crashes/bugs), and privacy
      nutrition label accuracy before submitting.
- [ ] Set the three Apple secrets in Supabase (`APPLE_PRIVATE_KEY`,
      `APPLE_TEAM_ID`, `APPLE_KEY_ID`) and deploy `apple-token-exchange` +
      the updated `delete-account` — not yet deployed as of this commit,
      code-complete only. See the exact commands given to the owner this
      session.
- [ ] Test the full Apple deletion flow end-to-end once deployed: sign in
      with Apple → confirm a row appears in `apple_refresh_tokens` → delete
      the account → confirm Apple's revoke actually succeeded (no reliable
      client-visible signal for this — check Edge Function logs).
- [ ] Not this week, explicitly deferred: `CKSyncEngine` migration
      (see `docs/CKSYNCENGINE.md`), accessibility/VoiceOver pass,
      localization-mechanism unification (3 mechanisms today).
- The owner may have more ideas after submission — ask.
