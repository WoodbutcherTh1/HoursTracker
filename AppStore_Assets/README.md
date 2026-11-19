# App Store Assets — HoursTracker

Real asset package for a 5‑language App Store submission:
**Hebrew (he), Arabic (ar), English (en), Russian (ru), Thai (th).**

## Contents

```
AppStore_Assets/
├── Metadata.md                 # Name / Subtitle / Promo / Description / Keywords / What's New (×5 languages)
├── README.md                   # this file
├── regenerate_screenshots.sh   # regenerates every image below end to end
├── Raw_Screenshots/            # unframed captures straight from the iOS Simulator
│   ├── english/ 1.png 2.png 3.png   # 1=Timer  2=Weekly graph  3=Shifts calendar
│   ├── hebrew/  1.png 2.png 3.png
│   ├── arabic/  1.png 2.png 3.png
│   ├── russian/ 1.png 2.png 3.png
│   └── thai/    1.png 2.png 3.png
├── frameit_config/             # fastlane `frameit` configs (device frame + headline), one per language
│   └── <lang>/Framefile.json, title.strings
├── _frame_assets/              # shared background + fonts + the Arabic headline renderer
├── Screenshots/                # final framed screenshots — upload these
│   └── <lang>/ 1.png 2.png 3.png
└── Promo/
    └── en.png he.png ar.png ru.png th.png   # emoji feature graphic per language
```

- **Every PNG in `Screenshots/` is 1320 × 2868** — the exact App Store size for the 6.9" display (iPhone 16/17 Pro Max).
- `Raw_Screenshots/` are **real captures of the running app** — an XCUITest (`HoursTrackerUITests/RealAppStoreScreenshotTests.swift`) launches the actual binary in the Simulator, seeds the `UITEST_SCREENSHOTS` demo dataset, switches the in-app language, and screenshots: Home while clocked in (Timer), Home while clocked out (weekly graph), and History with the month calendar expanded (Calendar).
- `Screenshots/` frames those real captures with a device bezel + localized headline via fastlane's `frameit`, using the exact device pixel size (1320×2868) to auto-select the iPhone 16/17 Pro Max frame.
- Arabic is a special case: ImageMagick's text renderer (what `frameit` uses for the headline) doesn't do Arabic letter-joining, so `frameit_config/arabic/Framefile.json` renders its title fully transparent, and `_frame_assets/render_arabic_headlines.sh` re-renders the three headlines with headless Chrome (which shapes Arabic/Hebrew/Thai correctly) before compositing them over `frameit`'s frame+background. English, Hebrew, Russian, and Thai render correctly straight out of `frameit`.

## Regenerate

```bash
xcrun simctl list devices   # find/boot a 6.9" simulator, e.g. "iPhone 16 Pro Max"
AppStore_Assets/regenerate_screenshots.sh <SIMULATOR_UDID>
```

Requires `brew install fastlane imagemagick` and a one-time `fastlane frameit download_frames`. Edit `Metadata.md`'s headlines and `frameit_config/<lang>/title.strings` together to change the on-image copy; edit `frameit_config/<lang>/Framefile.json` to change fonts/background/padding.

## Note on the DEBUG name injection

The localized screenshot names live in `HoursTracker/Utilities/ScreenshotDemoData.swift`, inside the file‑wide `#if DEBUG` block and only reachable behind `UITEST_SCREENSHOTS`. **It is excluded from Release/Archive builds entirely**, so the shipping app always shows the user's real name — no manual removal required before Archive.
