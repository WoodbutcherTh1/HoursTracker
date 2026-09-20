# HoursTracker — Design & Product Audit, Roadmap, and Design System
**Prepared by:** senior SwiftUI/watchOS engineering + product design + QA review
**Date:** 2026-09-20 · **Scope:** iPhone app, Watch app, widget, tests, themes, user guide
**Method:** read-only code inspection (file:line evidence), live App Store research (cited), then a prioritized roadmap and a design-system spec. No speculative features — every gap below was verified against the code.

---

## PART 1 — VERIFIED EXISTING FEATURES (evidence)

### iPhone app
| Feature | Evidence |
|---|---|
| 4-tab navigation: Home / History / Export / Settings, deep-linkable (`hourstracker://tab/…`, `action/clockIn|clockOut|scan`) | `HoursTrackerApp.swift:158–210, 283–302` |
| One-tap clock in/out with animated door button; live HH:MM:SS timer with gross/net toggle while clocked in | `HomeView.swift:1–22, 180–184` |
| Work sessions with day types (regular / rest day / holiday / sick), unpaid breaks, night-shift flag, notes, manual & AI-imported flags | `WorkSession.swift:5–75` |
| Israeli pay engine: 125%/150% overtime tiers (150%/175%/200% on rest days & holidays), weekly 42h standard, night 7h standard, sick-pay streak logic | `OvertimeCalculator.swift:33–70`, `WorkplaceSettings.swift:51–60` |
| Net-pay estimation: income tax, Bituach Leumi, health tax, credit points by marital status/children/spouse/retirement age | `DayPayBreakdown` fields, `OvertimeCalculator.swift:13–29`; `IsraeliTaxEstimator.swift`, `TaxCreditPointsCalculator.swift` |
| Custom payroll cycle start day (1–28) + up to two weekly rest days; holiday auto-fill from typical shift start | `WorkplaceSettings.swift:44–50, 63–68`; `HistoryPeriodHelper` |
| History: payroll-period navigation, Health-style week strip (swipe-to-expand), day filter, weekday-name toggle, per-period empty states, per-day delete, pay breakdown sheet | `HistoryView.swift:15–60, 699–849` |
| Export: PDF / CSV / TXT / DOCX / Markdown, range modes (this month, specific month, year, custom), day-type filter, export language choice | `ExportManager.swift:16–63`, `ExportView.swift:15–70` |
| Full data export/import (JSON document) for device migration | `FullDataExportManager.swift`, `FullDataExportSheet.swift` |
| Timesheet scanner: on-device Vision OCR + PDFKit, optional cloud-AI assist (user key), confidence flags, review sheet, import-conflict resolution | `TimesheetScannerManager.swift`, `BlankTimesheetEntryView.swift:137–149`, `MainTabView` routed `.scannerReview` |
| Payslip library: import, thumbnails, review state, detail with PDF preview, review-needed badge, delete w/ confirm | `PayslipLibraryView.swift:44–65`, `PayslipDetailView.swift:37–45, 100–110` |
| Account: Supabase email auth (8-digit OTP), profile (avatar w/ initials placeholder, name, email, member-since), change password, backup/sync of sessions+settings | `AccountSheet.swift`, `SupabaseAuthManager.swift`, `SupabaseAccountSyncManager.swift`, `AccountProfileStore.swift` |
| Optional CloudKit private-DB merge sync (entitlement-gated, NoOp fallback) | `CloudKitSyncManager.swift:1–80` |
| Widgets with interactive clock in/out (App Intents → App Group handoff, stateless widget), Live Activities on Lock Screen | `WidgetActions.swift:7–30`, `LiveActivityManager.swift:13–33` |
| Geofence arrival reminder (single CLCircularRegion) + clock-out & forgot-clock-out local notifications | `LocationReminderManager.swift:20–282` |
| Face ID App Lock + privacy overlay for app switcher | `AppLockController`, `HoursTrackerApp.swift:19–23` |
| AI assistant chat: tool-calling over local data, Gemini→OpenAI-compatible router, honest "not configured" state, no keyword guessing | `AssistantLLMRouter.swift:1–35`, `AssistantEngine.swift` |
| In-app feedback → Telegram (message + optional activity-log attachment) | `TelegramFeedbackSender.swift` |
| Localization EN/HE/AR with RTL layout, per-app language override, RTL-isolated name interpolation | `HoursTrackerApp.swift:40–42`, `HomeVitalityViews.swift:70–77`, `Localizable.xcstrings` |
| Theming: user-pickable accent (8 presets + full picker) & background (5 presets), applied app-wide incl. Watch tint & tab bar | `HomeAccentTheme.swift:24–55`, `AppBackgroundTheme.swift:16–53` |
| Onboarding (3 pages), in-app 7-slide User Guide that renders real components | `OnboardingView.swift`, `UserGuideSheet.swift` |
| Data-integrity engineering: transient-read protection vs silent wipe, corrupt-file quarantine, tombstone-based merges, export temp-file wipe on background | `PersistenceManager.swift:11–27`, `CorruptFileQuarantine.swift`, `HoursTrackerApp.swift:69–76` |

### Watch app (watchOS 10+)
- Structure mirrors phone: 4 paged tabs (Home/History/Export/Settings) with NavigationStacks; tint follows phone accent (`WatchMainTabView.swift:10–35`).
- Zero business logic on watch: renders a precomputed `WatchSnapshot` (all pay math done on phone); cached to disk for instant launch (`WatchSnapshot.swift:5–12`, `WatchSessionStore.swift:12–33`).
- Clock in/out, history browsing, settings toggles (hide widget pay, app lock, language), export request handed back to phone for the share sheet (`WatchSessionStore.swift:44–75`).
- Error surfacing for unreachable phone (`WatchHomeView.swift:33–36`).

### Tests (QA view)
- **38 unit-test files** covering: persistence/merge (`SyncMergeTests`, `SyncingPersistenceStoreTests`), calculators (`OvertimeCalculatorTests`, `PayRulesTests`, `TaxDeductionsCard`-adjacent math), scanner (`ScannerRowValidatorTests`, `TimesheetScannerBoundsTests`, `ScannerLLMRouterTests`), assistant (`AssistantEngineTests`, `AssistantPlanTests`, `AssistantToolboxTests`), security (`AppLockTests`, `WorkerIDKeychainPersistenceTests`, `ProtectedFileWriterTests`), i18n (`AppLanguagePreferenceTests`), corruption (`CorruptFileQuarantineTests`), location (`LocationPermissionFlowTests`, `LocationReminderPolicyTests`).
- **1 UI-test file** (`ScreenshotTests.swift`) — screenshot seeding only, **no functional UI test coverage**.

---

## PART 2 — VERIFIED GAPS (not speculation — each checked in code)

### A. Localization / RTL
1. **Watch app is English-only with hardcoded strings.** Verified literals: "Clock In"/"Clock Out" (`WatchHomeView.swift:66`), "Good morning/afternoon/evening" (`WatchHomeView.swift:175–177`), "Refresh", "Open HoursTracker on your iPhone once to sync." (`WatchHomeView.swift:39–49`), "Net pay", "No shifts", "Show all", "All shifts" (`WatchHistoryView.swift:69–164`), "This month/This year", "No data in this range" (`WatchExportView.swift:22–65`), all Settings rows (`WatchSettingsView.swift:31–102`). A Hebrew/Arabic user gets an English watch app. Also **no RTL layout on Watch**.
2. **Watch greeting logic duplicated, not shared**: `DaypartGreeting` exists shared-able on phone (`HomeVitalityViews.swift:22–37`) but Watch re-implements thresholds inline (and with different evening cutoff: 17–22 vs phone 17–21) — drift risk. (`WatchHomeView.swift:174–178`)
3. Guide language pill exists, but guide copy lives in-code (`GuideCopy`), not in the string catalog — acceptable, but it means translators must edit Swift. (`UserGuideSheet.swift:210–330`)

### B. Typography / Dynamic Type / accessibility
4. **Zero `@ScaledMetric` or `relativeTo:` usage in the entire project** (verified by search). All `.system(size:)` fixed fonts do not scale with Dynamic Type: 33 instances on Watch, 7 in `HomeVitalityViews`, 7 in `AccountSheet`, 6 in `MonthlyTrendCard`, more across Onboarding/Home/History. Semantic styles (.headline etc.) elsewhere do scale — the app is *inconsistent* under large type.
5. Accessibility labels are used widely (40+ sites, good), but **`accessibilityHint` is used 0 times** and decorative neon/aurora elements are not always `accessibilityHidden`. VoiceOver users get labels without usage hints on custom controls (door button, swatches).
6. **Light mode is intentionally absent** — `.preferredColorScheme(.dark)` is hard-pinned app-wide (`HoursTrackerApp.swift:43–47`). The theming system (accent + background pickers) is dark-only; `HomeNeon` colors are fixed dark-surface tokens (`HomeVitalityViews.swift:8–14`). This is a *product decision on record*, but it means "premium light/dark modes" remains a gap vs. system-integrated competitors.

### C. UI states
7. Loading/error/empty states are **strong on iPhone core screens** (History `historyEmpty`/`historyEmptyPeriod` `HistoryView.swift:822–849`; Payslip library `PayslipLibraryView.swift:171–184`; Export preview `ExportView.swift:135`; scanner `ContentUnavailableView` `TimesheetScannerView.swift:457`; progress caps on Account/Contact sheets) — but **inconsistent on secondary paths**: e.g. Watch uses plain caption text for empty/error; several sheets show bare `ProgressView` with no label or skeleton.
8. **No network-error retry UI on Account sync paths** beyond raw error text; failures map to localized strings but there is no "Retry" affordance pattern.

### D. Guide ↔ app drift (QA finding — user-facing)
9. **Assistant slide says "Tap the floating icon"** (`UserGuideSheet.swift:322–330`) but the assistant lives in each tab's navigation bar — the file's own header comment and `MainTabView.swift:202–204` say so. Users are taught a UI element that no longer exists.
10. **Payslip slide says "then share or export the PDF"** (`UserGuideSheet.swift:310–315`) but `PayslipDetailView` offers **preview + delete only — no share/export action** (verified: no ShareLink/ShareSheet/UIActivityViewController in that file; only History/Export have share sheets). The guide promises a missing feature.
11. Guide does not cover: account sign-up/backup, widgets & Live Activities, arrival reminders, App Lock — the newest, most differentiating features.

### E. Test coverage (QA view)
12. No functional UI tests (only screenshot seeding). Critical flows — clock in/out, OTP entry, scanner review, export share — have zero automated end-to-end verification.
13. Watch target has **no test target at all** (only iOS tests exist per `project.yml`).

### F. Architecture notes (design-system readiness)
14. Theme tokens exist but are **scattered across three homes**: `HomeNeon` (fixed struct), `HomeAccentTheme` (user accent), `AppBackgroundTheme` (user background) — plus per-view `Color.white.opacity(...)` literals everywhere. There is no single semantic palette (surface/card/stroke/positive/warning) to build on.
15. Spacing/typography are ad-hoc per view (`HomeLayoutMetrics` is Home-only; other screens hardcode 12/14/16/18 paddings).

---

## PART 3 — MARKET RESEARCH (cited, App Store + official sources)

### Direct named competitor: Hours Tracker (Cribasoft) — iOS, 4.8★, 56K ratings
Source: https://apps.apple.com/us/app/hours-tracker-time-tracking/id336456412
Features it advertises that HoursTracker (ours) lacks: **breaks/pauses with automatic breaks**, **tips & mileage tracking**, **± adjustments to entries**, **multiple jobs**, **time rounding (6-min etc.)**, **tags & filtering**, **clock-in reminders on work days**, **web-based reporting (subscription)**, geofence *auto* clock-in/out (ours reminds only). Free edition limits (3 jobs / 21 days) drive its monetization.

### Israeli-context landscape
- Local competition is largely **B2B attendance platforms** (Timewatch, Clockworks, Lynxbe — payroll modules with 125%/150% OT per Hours of Work and Rest Law 5711-1951; sources: timewatch.co.il, clockworks.co.il, lynxbe.co.il). Verified: **no polished consumer Hebrew/Arabic app combining personal tracking + Israeli pay estimation + payslip analysis** surfaced in App Store searches; the only consumer hit, "מחשבון שעות" (Applorium, https://apps.apple.com/il/app/id6745176754), is a generic hours *calculator* (1 rating, no tracking, no payslip features, accessibility section empty).
- Web calculators (team3.co.il, formy.co.il, gclocks.com) confirm demand for 125%/150% and net estimation, but are single-shot tools — no history, no scanning.
- **Strategic conclusion:** our moat is the *Israeli worker* niche (RTL, ₪, tax/credit-points, payslip import, holiday rules). Competing with Cribasoft feature-for-feature (multi-job, tags) would be bloat; deepening the local niche is the wedge.

### Horizontal benchmarks (design/quality bar)
- **Toggl Track** (iOS, 4.8★, 9.6K): cross-device sync, calendar integration, Siri, widgets, Pomodoro, offline-first sync (https://apps.apple.com/us/app/toggl-track-hours-time-log/id1291898086). Bar set: *sync reliability & quick entry everywhere*.
- **Timesheet / Work Log - Shift Tracker** (AR Productions, 4.8★, 4.3K): pay-period totals, up to 3 OT rule sets, premium/differential hours, quick shifts, auto break deduction, cloud sync (https://apps.apple.com/us/app/work-log-shift-tracker/id1578126960). Bar set: *pay-period-first information architecture* (ours already has this via payroll cycle — a strength to advertise).
- **timesheet.io** (May 2026 roundup, timesheet.io/en/blog/best-time-tracking-apps-ios): native Watch app + Siri + Action Button + NFC as the 2026 differentiator set.
- US Dept. of Labor's **WorkWise Timesheet** (dol.gov/agencies/whd/WorkWise-timesheet) validates gov-level interest in worker-facing hour records — ours is stronger (pay estimation).

### Feature-existence matrix (verified)
| Capability | Ours | Cribasoft | Toggl | Work Log |
|---|---|---|---|---|
| Clock in/out + live timer | ✅ | ✅ | ✅ | ✅ |
| Pay-period-first history | ✅ | pay periods | calendar | ✅ |
| Country-specific pay law engine (IL) | ✅ unique | ❌ | ❌ | US rules |
| Payslip import + estimate-vs-actual | ✅ unique | ❌ | ❌ | ❌ |
| Timesheet photo→OCR import | ✅ | ❌ | ❌ | ❌ |
| Localized HE/AR + RTL | ✅ | ❌ (EN) | partial | ❌ (EN) |
| Watch companion | ✅ (EN-only UI) | ✅ | ✅ | ❌ |
| Interactive widgets + Live Activity | ✅ | widget | widget | ❌ |
| Breaks/pauses tracking | ❌ gap | ✅ | n/a | ✅ |
| Multiple jobs | ❌ | ✅ | projects | ✅ (Pro) |
| Time rounding / ± adjustments | ❌ | ✅ | ❌ | ✅ |
| Light mode | ❌ (dark-only by design) | ✅ | ✅ | ✅ |
| Functional UI tests | ❌ | n/a | n/a | n/a |

---

## PART 4 — PRIORITIZED ROADMAP (not feature bloat)

**Principle:** every item either (a) fixes a verified defect/drift, (b) removes friction on an existing flow, or (c) deepens the verified Israeli-worker moat. Explicitly *deferred* (bloat for this product): multi-job support, tags, tips/mileage, Pomodoro, web dashboard, subscriptions.

### P0 — Correctness & trust (ship first; small, high-certainty)
1. **Fix guide drift** (gaps 9–10): assistant nav-bar copy; payslip slide matches preview/review/delete reality. *(Done in this pass — see Part 6.)*
2. **Localize the Watch app fully** (HE/AR + RTL), reusing the phone's string catalog keys via a shared `WatchL10n` shim compiled into the watch target; share `DaypartGreeting` instead of the drifted re-implementation (gap 2). Watch users are the same users; two languages in one brand is a bug, not a feature.
3. **Dynamic Type pass on critical flows**: convert fixed `.system(size:)` to `@ScaledMetric`/`relativeTo:` on Home timer/door, History rows, Export form, Account sheet (gap 4). Accessibility is also an App Store reviewability and EU-accessibility-requirement matter.
4. **Loading/empty/error state standardization**: one `HTStateView` component (loading with label + retry, empty with icon/title/hint/CTA, error with retry) adopted by Watch screens + secondary sheets (gaps 7–8).

### P1 — Premium experience (the design-system build-out)
5. **Semantic design tokens** (Part 5): introduce `HTTheme` namespace — palette (surfaceElevated, strokeSubtle, textPrimary/Secondary, positive/warning/destructive, accent±deep), spacing scale (4/8/12/16/20/28), type scale (display/title/headline/body/footnote/caption as `relativeTo:` styles), radius tokens (10/14/18). Migrate `HomeNeon` and the ad-hoc whites *incrementally* — no big-bang restyle; screenshots must stay pixel-stable.
6. **Light mode as a first-class option** (opt-in, default stays dark): tokens make this cheap — define light equivalents of surface/stroke/text; keep neon accent. Ship behind the existing theme picker as "Appearance: Dark / Light / Auto". *(Only after P1.5; this is the single biggest perceived-premium win vs. the dark-only status quo.)*
7. **VoiceOver completeness**: add hints to the door button, swatches, week strip, pay toggle; mark aurora/particles/glow decorations `accessibilityHidden`; audit rotor navigation on History's table-like week grid.
8. **Functional UI tests** for the money paths: clock in → clock out → history row appears; export share sheet presents; OTP entry → success; scanner review → import. Run on every PR.

### P2 — Moat-deepening (new capability, still not bloat)
9. **Breaks during shift** (the one Cribasoft/Work Log feature our users plausibly need): `WorkSession.breakMinutes` already exists as a stored unpaid deduction — extend with a mid-shift "Start break / End break" that accrues `breakMinutes` live, shown on Watch + Live Activity. Schema-compatible; no migration.
10. **"Where's my money?" period report**: a shareable one-page PDF (per payroll period): hours by tier, gross→net waterfall, estimate vs. payslip delta when one exists. Reuses existing calculators + PDF renderer; zero new math.
11. **Widget polish**: lock-screen accessory widget (clock-in state at a glance) — iOS 17 API, small surface, high visibility.
12. **Reminder to clock in on work days** (Cribasoft parity, tiny): reuse `expectedShiftStartHour` + UNUserNotificationCenter.

### Explicit non-goals (recorded so future reviews don't re-litigate)
Multi-job/projects, tags, tips/mileage, geofence *auto* punch (legal-trust risk for wage disputes), web dashboard, AI beyond the existing assistant, subscriptions/ads.

---

## PART 5 — DESIGN SYSTEM SPEC (tokens & rules)

### 5.1 Color tokens (semantic; dark values today, light variants in P1.6)
```
HTTheme.Colors
  accent            = HomeAccentTheme.shared.accent (user-set; default #26F273)
  accentDeep        = accent.darkened(0.55) or preset deep
  positive          = accent (success semantics reuse accent)
  warning           = #FFB238 (Amber preset)
  destructive/coral = #F24759 / deep #B81F38 (HomeNeon.coral — semantic: clocked-in, delete)
  surfaceBackground = AppBackgroundTheme.shared.background (user-set; default #0A0D0F)
  surfaceCard       = #171A1E (HomeNeon.card)
  surfaceElevated   = #1F2328 (new: sheets, popovers)
  strokeSubtle      = Color.white.opacity(0.08)  (tokenize the current literal)
  strokeStrong      = Color.white.opacity(0.16)
  textPrimary       = .white
  textSecondary     = Color.white.opacity(0.72)
  textTertiary      = Color.white.opacity(0.45)
```
Rules: components reference tokens only — never `Color.white.opacity(x)` inline; coral is reserved for active-session & destructive semantics (already the codebase's stated rule in `HomeAccentTheme.swift:36–39`); accent is the only user-recolorable hue.

### 5.2 Typography (Dynamic Type–safe)
```
HTTheme.Type
  display  = .system(size: 52, weight: .light, design: .rounded) relativeTo .largeTitle  (live timer)
  title    = .title2.weight(.bold).rounded()          (greeting, screen titles)
  headline = .headline                                  (card titles)
  body     = .body                                      (rows)
  callout  = .callout.monospacedDigit()                 (all numerals — already the pattern)
  footnote = .footnote
  caption  = .caption
```
Rules: every fixed size must declare `relativeTo:`; numerals always `.monospacedDigit()`; no font below `.caption2`; watch text ≥ 10pt equivalents using watchOS text styles.

### 5.3 Spacing / shape / elevation
```
space: 4, 8, 12, 16, 20, 28   (card padding 16; screen gutter 18; section gap 20)
radius: card 14, sheet 18, control capsule, thumb 10
elevation: cards = surfaceCard + strokeSubtle 1px + shadow(accent/destructive, radius 8, opacity ≤0.25)
           decoration glow allowed only on: door button, badge, primary CTA
```

### 5.4 Navigation & information architecture (as-built rules)
- iPhone: fixed 4 tabs (Home/History/Export/Settings) — matches Work Log's pay-period-first pattern; do not add tabs; secondary surfaces are sheets with `.medium/.large` detents (existing convention).
- Watch: keep 4 paged tabs mirroring phone; page order == phone tab order; every screen must render meaningfully with `.empty` snapshot (cached or placeholder + sync hint, localized).
- Sheets: one routed sheet per level (`MainSheetRoute` pattern) — never competing presentations.
- Deep links: `hourstracker://tab/{home|history|export|settings}`, `action/{clockIn|clockOut|scan}` — stable public contract used by widget + quick actions.

### 5.5 States (every async surface implements all four)
```
loading: HTStateView.loading(label)   — ProgressView + localized label (never bare)
empty:   HTStateView.empty(icon, title, hint, action?) — matches History/Payslip pattern
error:   HTStateView.error(message, retry) — Retry re-triggers the failed op inline
offline/watch-disconnected: snapshot cache + "Open on iPhone to sync" hint (localized!)
```

### 5.6 Localization & RTL rules (as-built, extend to Watch)
- All user-visible strings via `L10n`/String Catalog (en/he/ar); guide-style per-language copy is acceptable only in self-contained teaching UI.
- RTL: environment `layoutDirection` flows from `AppLanguageController`; embed Latin tokens (emails, codes) with Bidi isolates (`\u{2068}…\u{2069}` — the `DaypartGreeting` pattern); chrome in mixed-direction sheets pins direction explicitly (the guide's `leftToRight` chrome pattern).
- Dates/currency via `AppLocale.makeDateFormatter` + `PayFormatter` — never `String(format:)` with hardcoded order (Watch's `"Day \(n)"` violates this today).

### 5.7 Watch design language
- Mirror phone tokens: accent from snapshot, coral for clocked-in, surface cards with 16pt radius.
- Minimum hit target: full-width `borderedProminent`; captions ≥ 9pt; use watchOS native styles over custom sizes where possible.
- Live timer uses `Text(date, style: .timer)` (already) — keep; do not port the phone's tick loop.

---

## PART 6 — USER GUIDE UPDATE (shipped in this pass)

Corrected two drifts inside `UserGuideSheet.swift` (code + en/he/ar copy):
1. **Assistant slide**: "Tap the floating icon…" → teaches the *navigation-bar* sparkles icon (all three languages).
2. **Payslip slide**: removed the unshipped "share or export the PDF" promise → now describes what `PayslipDetailView` actually does (open → preview → review flag → delete) and points to the Export tab for reports.

Header comment updated to record the QA rationale. Recommended (not in this pass): add guide slides for Account/backup, Widgets, and Arrival reminders under the P0/P1 roadmap.

---

*Evidence base: 30+ source files read in full or in part; 38 test files enumerated; all App Store claims from live listings fetched 2026-09-20 (URLs above).*
