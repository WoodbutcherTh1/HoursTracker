# HoursTracker — Master Agent Brief status

Official name: **HoursTracker**  
Watch branch: `cursor/app-store-marketing-and-watch-f642`  
Watch PR: https://github.com/WoodbutcherTh1/HoursTracker/pull/16 (draft — await Mac Simulator)

| Agent | Status | Notes |
|-------|--------|--------|
| 1 Merge & Stabilize Watch | **Done** | `main` merged; xcstrings = main + watch keys |
| 2 App Name Unification | **Done** | `TrackersHour\|HourTrackers` → 0 hits |
| 3 Marketing Screenshots Fix | **Partial → waiting on Agent 5 Mac run** | EN recomposed; he/ar blocked on CoreText binary + raw recapture |
| 4 Watch PR + App Preview storyboard | **Done** | PR #16 draft; `docs/APP_PREVIEW_STORYBOARD.md` |
| 5 CoreText Headline Renderer | **Code ready — awaiting Mac run/verify after 17:00** | Branch `cursor/coretext-headline-renderer-ad5d` |

## Agent 5 detail
- Swift CLI rewritten: explicit RTL, allow-listed fonts only, exit **1** on font failure (no system fallback).
- Contract unit tests (Linux-safe): `python3 scripts/test_headline_renderer_contract.py`
- Mac runbook: `docs/CORETEXT_HEADLINE_MAC_RUNBOOK.md`
- Visual PNG approval still **mandatory** before marking Agent 3 complete.
