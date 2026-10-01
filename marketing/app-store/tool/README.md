# App Store frame renderer

Composes the marketing frames (headline, 3D phone, neon ribbon, pop-out, Live
Activity bubble) around the raw screenshots from the "App Store Screenshots"
workflow, at 1320×2868.

    npm i playwright-core@1.56
    node render.js example-hebrew.json   # writes <out>-1.png, <out>-2.png, ...

Styles: `hero` (chosen direction), `panorama`, `numeral`, `popout`. Chromium
comes from Playwright's headless shell. Fonts (Rubik, Readex Pro, Heebo, Space
Grotesk) are Google Fonts under the SIL Open Font License, bundled in `fonts/`.
