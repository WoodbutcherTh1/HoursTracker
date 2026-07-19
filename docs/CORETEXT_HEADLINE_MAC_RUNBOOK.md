# CoreText headline renderer — Mac runbook

**Status:** Code ready on branch `cursor/coretext-headline-renderer-ad5d`.  
**Blocked on:** macOS (CoreText / AppKit). Cloud Linux cannot execute the binary.

## Build

```bash
cd /path/to/HoursTracker
swiftc -O scripts/render_headline_coretext.swift -o scripts/render_headline_coretext
chmod +x scripts/render_headline_coretext
```

## Smoke test (one word, visual check — mandatory)

```bash
export HT_HEADLINE_TEXT="שלום"
./scripts/render_headline_coretext \
  "AppStoreScreenshots/watch/marketing/fonts/Rubik[wght].ttf" \
  56 800 FFFFFFF0 /tmp/ht-he-smoke.png
open /tmp/ht-he-smoke.png

export HT_HEADLINE_TEXT="مرحبا"
./scripts/render_headline_coretext \
  "AppStoreScreenshots/watch/marketing/fonts/Cairo[slnt,wght].ttf" \
  56 800 FFFFFFF0 /tmp/ht-ar-smoke.png
open /tmp/ht-ar-smoke.png
```

Expect: transparent PNG, correct script shaping, **no** Latin/system font glyphs.  
If the font file is missing → exit **1** with an explicit allow-list error (no Helvetica fallback).

## Full he/ar marketing recompose

```bash
# 1) Recapture raws if History demo density is still stale:
#    scripts/capture_iphone_marketing_raw.sh   # Simulator UITest

# 2) Compose all langs (uses CoreText binary for he/ar):
python3 scripts/compose_iphone_marketing_screenshots.py --device 6.9-1320x2868 --all

# 3) Hard dimension gate:
python3 scripts/validate_iphone_marketing_dimensions.py
```

## Contract tests (safe on Linux / Cloud)

```bash
python3 scripts/test_headline_renderer_contract.py
```

## After visual approval

- Replace any `needs-recapture` artifact labels for he/ar.
- Mark Agent 3 **complete** in `docs/MASTER_AGENT_BRIEF_STATUS.md`.
- **Do not** treat screenshots as final until a human eyeballs every language.
