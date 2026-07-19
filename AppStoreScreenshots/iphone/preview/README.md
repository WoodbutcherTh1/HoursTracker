# iPhone App Preview (App Store Connect)

## Deliverables

| File | Spec |
|------|------|
| `HoursTracker-AppPreview-en-886x1920.mp4` | English |
| `HoursTracker-AppPreview-he-886x1920.mp4` | Hebrew |
| `HoursTracker-AppPreview-ar-886x1920.mp4` | Arabic |

All are **886×1920**, H.264 High@L4.0, **30 fps CFR**, **~24.5 s**, **no audio**, ~28 MB — accepted portrait size for 6.9" / 6.5" / 6.3" / 6.1" in App Store Connect.

## How it was built

- Marketing screenshots from `../marketing/6.9-1320x2868/{lang}/`
- Original AI people stills in `people/` (generated for HoursTracker; not stock photos)
- Compose: `python3 scripts/compose_iphone_app_preview.py --lang en` (or `--all`)

## Alternate: live simulator recording

For a pure on-device capture (no people stills):

```bash
bash scripts/record_iphone_app_preview.sh
```
