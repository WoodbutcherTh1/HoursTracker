# HoursTracker — iPhone App Preview storyboard

> Apple App Preview is **iPhone only** (Watch is not supported).  
> Target size: **886×1920**. Duration: **15–30 seconds**.  
> This is a planning doc only — recording needs a real device or Simulator screen capture.

## Scene plan (≈24s)

| # | Time | Scene | On-screen motion |
|---|------|--------|------------------|
| 1 | 0:00–0:04 | **Home (clocked out)** | Launch settles on neon Home. Brand wordmark + greeting visible. Ambient aurora / particles drift. Door CTA pulses lightly. |
| 2 | 0:04–0:09 | **Clock In → live timer** | Tap Clock In. Door opens. Timer starts counting. Basic gross ticker ticks up. Weekly sparkline today’s column shows **loading / pulse** (not frozen `00:00`). |
| 3 | 0:09–0:14 | **Sparkline + stats** | Hold on Home. Sparkline ridge glow travels. Month/week/today stat cards breathe. Optional subtle scroll of the week row. |
| 4 | 0:14–0:19 | **History** | Switch to History tab. Week strip lands on a dense demo day; multi-shift list scrolls briefly. Toggle gross/net if visible. |
| 5 | 0:19–0:24 | **Export → Settings** | Quick cut to Export (format chips). Then Settings scrolled to **pay rules / tax credits**. End on brand-safe dark chrome. |

## Notes
- Use `HT_SCREENSHOT_MODE=1` demo data only — never real worker PII.
- Keep **dark** color scheme for the whole clip (matches Home neon).
- Headline fonts for stills: Montserrat ExtraBold (en) / Cairo–Tajawal (ar) / Rubik–Assistant (he). Preview video itself uses in-app UI fonts.
- Optional end card (last 1s): “HoursTracker” wordmark only — no competitor copy.

## Capture checklist (human / Mac)
- [ ] Record 886×1920 (or crop from 6.9\" simulator)
- [ ] Trim to 15–30s, no audio required
- [ ] Export H.264 / `.mp4`
- [ ] Spot-check he + ar launches separately if shipping localized previews
