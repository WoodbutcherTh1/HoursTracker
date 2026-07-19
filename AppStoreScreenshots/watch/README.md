# Watch App Store screenshots

## Official sizes (App Store Connect, verified 2026-07-18)

Source: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

| Slot | Simulator | Pixels |
|------|-----------|--------|
| Series 11 / 10 (45mm-class) | Apple Watch Series 11 (46mm) | **416 × 496** |
| Ultra 3 (49mm) | Apple Watch Ultra 3 (49mm) | **422 × 514** |

ASC rule: **use the same watch screenshot size across all localizations** for a given upload.
Both slots are captured here so you can choose; do not mix sizes in one ASC submission.

## Capture

```bash
cd /Users/humussalad/FingerPrint
./scripts/capture_watch_screenshots.sh
# or: fastlane watch_screenshots
```

Uses `HT_SCREENSHOT_MODE=1` + `HT_SCREENSHOT_LANG=en|he|ar` (mid-shift demo, RTL for he/ar).

## Layout (12 PNGs)

```
AppStoreScreenshots/watch/
  series11-416x496/          ← 416×496 (ASC Series 11 / 10)
    en/ 01-clock.png  02-recent.png
    he/ 01-clock.png  02-recent.png
    ar/ 01-clock.png  02-recent.png
  ultra3-422x514/            ← 422×514 (ASC Ultra 3)
    en/ 01-clock.png  02-recent.png
    he/ 01-clock.png  02-recent.png
    ar/ 01-clock.png  02-recent.png
```

## RTL checks (he / ar)

- Clock: Recent list control mirrored to visual **left**; localized Clock Out + timer.
- Recent: back chevron points **right**; list text **right-aligned**; title on the left.
