// Renders App Store frames: node render.js <config.json>
// config: { style, lang, out, slides:[{img, head:[pre,hl,post], sub, chip:{k,v}, big, pop:{x,y,w,h}}] }
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright-core');

const W = 1320, H = 2868;
const ACCENT = '#2FF07F';
const cfg = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const rtl = cfg.lang !== 'english';
const font = cfg.lang === 'arabic' ? "'Readex Pro'" : cfg.lang === 'hebrew' ? "'Rubik'" : "'Space Grotesk','Rubik'";
const bodyFont = cfg.lang === 'arabic' ? "'Readex Pro'" : "'Rubik'";
const fontsCss = fs.readFileSync(path.join(__dirname, 'fonts/fonts.css'), 'utf8')
  .replace(/url\(([^)]+)\)/g, (m, f) => `url(file://${path.join(__dirname, 'fonts', f.replace(/['"]/g, ''))})`);
const b64 = f => 'data:image/jpeg;base64,' + fs.readFileSync(f).toString('base64');

// Phone: 962x2090 screen inside a titanium frame.
const phone = (img, extra = '') => `
  <div class="phone" style="${extra}">
    <div class="screen"><img src="${b64(img)}"/><div class="island"></div></div>
  </div>`;

const headline = (h, size) => `<h1 style="font-size:${size}px">${h[0]}<span class="hl">${h[1]}</span>${h[2] || ''}</h1>`;
const chip = (c, pos) => c ? `<div class="chip" style="${pos}"><div class="k">${c.k}</div><div class="v">${c.v}</div></div>` : '';

const styles = {
  // A — one continuous neon ribbon across all five frames.
  panorama(slides) {
    const n = slides.length;
    const ribbon = `<svg class="ribbon" width="${W * n}" height="${H}" viewBox="0 0 ${W * n} ${H}">
      <defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="${ACCENT}"/><stop offset=".5" stop-color="#38E1FF"/><stop offset="1" stop-color="${ACCENT}"/></linearGradient>
      <filter id="blur"><feGaussianBlur stdDeviation="28"/></filter></defs>
      <path d="${ribbonPath(n)}" fill="none" stroke="url(#g)" stroke-width="120" filter="url(#blur)" opacity=".6"/>
      <path d="${ribbonPath(n)}" fill="none" stroke="url(#g)" stroke-width="14" stroke-linecap="round"/>
      <path d="${ribbonPath(n, 90)}" fill="none" stroke="#38E1FF" stroke-width="4" opacity=".7"/>
      <path d="${ribbonPath(n, -80)}" fill="none" stroke="${ACCENT}" stroke-width="3" opacity=".45" stroke-dasharray="2 26" stroke-linecap="round"/>
    </svg>`;
    const frames = slides.map((s, i) => {
      const tilt = i % 2 ? 3 : -3;
      return `<section style="left:${(rtl ? n - 1 - i : i) * W}px">
        <div class="glow" style="top:1350px;left:160px"></div>
        <header>${headline(s.head, 112)}<p>${s.sub}</p></header>
        ${phone(s.img, `position:absolute;left:155px;top:760px;transform:rotate(${tilt}deg)`)}
        ${chip(s.chip, `top:${i % 2 ? 2280 : 1180}px;${i % 2 ? 'left' : 'right'}:40px`)}
      </section>`;
    }).join('');
    return { width: W * n, html: ribbon + frames };
  },

  // A+ — panorama ribbon, 3D-tilted phones, a magnified pop-out of the key UI,
  // an optional Live Activity island floating above, sparks and film grain.
  hero(slides) {
    const n = slides.length;
    const k = 962 / W;
    const sparks = Array.from({ length: 70 }, (_, j) => {
      const x = (j * 997) % (W * n), y = 900 + ((j * 613) % 1900), r = 2 + (j % 4) * 2;
      return `<circle cx="${x}" cy="${y}" r="${r}" fill="${j % 3 ? ACCENT : '#38E1FF'}" opacity="${0.25 + (j % 5) * 0.12}"/>`;
    }).join('');
    const ribbon = `<svg class="ribbon" width="${W * n}" height="${H}" viewBox="0 0 ${W * n} ${H}">
      <defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="${ACCENT}"/><stop offset=".5" stop-color="#38E1FF"/><stop offset="1" stop-color="${ACCENT}"/></linearGradient>
      <filter id="blur"><feGaussianBlur stdDeviation="30"/></filter><filter id="spark"><feGaussianBlur stdDeviation="3"/></filter></defs>
      <path d="${ribbonPath(n)}" fill="none" stroke="url(#g)" stroke-width="150" filter="url(#blur)" opacity=".55"/>
      <path d="${ribbonPath(n)}" fill="none" stroke="url(#g)" stroke-width="16" stroke-linecap="round"/>
      <path d="${ribbonPath(n, 100)}" fill="none" stroke="#38E1FF" stroke-width="4" opacity=".7"/>
      <path d="${ribbonPath(n, -90)}" fill="none" stroke="${ACCENT}" stroke-width="5" opacity=".5" stroke-dasharray="2 30" stroke-linecap="round"/>
      <g filter="url(#spark)">${sparks}</g>
    </svg>`;
    const frames = slides.map((s, i) => {
      const col = rtl ? n - 1 - i : i;
      const ry = (i % 2 ? -1 : 1) * (rtl ? -1 : 1) * 14;
      const phoneTop = 900, screenTop = phoneTop + 24;
      let pop = '';
      if (s.pop) {
        const p = s.pop, scale = 1.28;
        const w = p.w * k * scale, h = p.h * k * scale;
        const cy = screenTop + (p.y + p.h / 2) * k + (s.popShift || 0);
        pop = `<div class="pop" style="width:${w}px;height:${h}px;top:${cy - h / 2}px;left:${(W - w) / 2 + (s.popX || 0)}px">
          <img src="${b64(s.img)}" style="position:absolute;width:${W * k * scale}px;left:${-p.x * k * scale}px;top:${-p.y * k * scale}px"/></div>`;
      }
      const island = s.island ? `<div class="live"><div class="dot"></div><div class="t">${s.island.t}</div><div class="v">${s.island.v}</div></div>` : '';
      return `<section style="left:${col * W}px">
        <div class="glow" style="top:1300px;left:160px"></div>
        <header><div class="eyebrow"><span class="mark"></span>HoursTracker</div>${headline(s.head, 116)}<p>${s.sub}</p></header>
        <div class="stage">${phone(s.img, `position:absolute;left:155px;top:${phoneTop}px;transform:rotateY(${ry}deg) rotateZ(${-ry / 7}deg)`)}</div>
        ${island}${pop}
        ${chip(s.chip, `top:${s.chipTop || 2350}px;${(i % 2) ^ rtl ? 'left' : 'right'}:60px`)}
      </section>`;
    }).join('');
    return { width: W * n, html: ribbon + frames + '<div class="grain"></div>' };
  },

  // B — a giant outlined number behind the phone.
  numeral(slides) {
    const frames = slides.map((s, i) => `<section style="left:${i * W}px">
        <div class="big">${s.big || ''}</div>
        <div class="glow" style="top:1500px;left:160px"></div>
        <header>${headline(s.head, 112)}<p>${s.sub}</p></header>
        ${phone(s.img, 'position:absolute;left:155px;top:1240px')}
      </section>`).join('');
    return { width: W * slides.length, html: frames };
  },

  // C — the key part of the screen pops out, magnified, over the phone.
  popout(slides) {
    const k = 962 / W; // screenshot px -> on-phone px
    const frames = slides.map((s, i) => {
      const p = s.pop;
      const scale = 1.3;
      const phoneTop = 980, screenLeft = 155 + 24, screenTop = phoneTop + 24;
      let shown = '';
      if (p) {
        const w = p.w * k * scale, h = p.h * k * scale;
        const cy = screenTop + (p.y + p.h / 2) * k;
        shown = `<div class="pop" style="width:${w}px;height:${h}px;top:${cy - h / 2}px;left:${(W - w) / 2}px">
          <img src="${b64(s.img)}" style="position:absolute;width:${W * k * scale}px;left:${-p.x * k * scale}px;top:${-p.y * k * scale}px"/></div>`;
      }
      return `<section style="left:${i * W}px">
        <div class="glow" style="top:1200px;left:160px"></div>
        <header>${headline(s.head, 118)}<p>${s.sub}</p></header>
        ${phone(s.img, `position:absolute;left:155px;top:${phoneTop}px;filter:brightness(.75)`)}
        ${shown}
      </section>`;
    }).join('');
    return { width: W * slides.length, html: frames };
  }
};

// A wave that crosses every frame edge at a different height, so neighbouring
// frames visibly connect in the App Store row.
function ribbonPath(n, shift = 0) {
  const ys = [1100, 2500, 1300, 2600, 1150, 2400];
  let d = `M -200 ${ys[0] + shift}`;
  for (let i = 0; i < n; i++) {
    const x0 = i * W, x1 = (i + 1) * W;
    d += ` C ${x0 + 520} ${ys[i] + shift}, ${x1 - 520} ${ys[i + 1] + shift}, ${x1} ${ys[i + 1] + shift}`;
  }
  return d + ` L ${n * W + 200} ${ys[n] + shift}`;
}

(async () => {
  const { width, html } = styles[cfg.style](cfg.slides);
  const page = `<!doctype html><html dir="${rtl ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><style>
    ${fontsCss}
    *{margin:0;padding:0;box-sizing:border-box}
    body{width:${width}px;height:${H}px;background:#05080A;overflow:hidden;position:relative;font-family:${bodyFont}}
    body::before{content:"";position:absolute;inset:0;background:
      radial-gradient(1200px 900px at 20% 0%, rgba(47,240,127,.10), transparent 60%),
      radial-gradient(1400px 1000px at 80% 100%, rgba(56,225,255,.08), transparent 60%);}
    section{position:absolute;top:0;width:${W}px;height:${H}px;overflow:visible}
    header{position:absolute;top:200px;left:110px;right:110px;text-align:${rtl ? 'right' : 'left'};z-index:5}
    h1{font-family:${font};font-weight:800;color:#F4F7F6;line-height:1.08;letter-spacing:${rtl ? '0' : '-2px'}}
    .hl{color:${ACCENT};text-shadow:0 0 40px rgba(47,240,127,.55),0 0 90px rgba(47,240,127,.35)}
    header p{margin-top:34px;font-size:50px;line-height:1.35;color:#A3ABB2;font-weight:400}
    .phone{width:1010px;height:2138px;border-radius:150px;padding:24px;z-index:3;
      background:linear-gradient(145deg,#5a6068 0%,#1a1d21 18%,#0c0e10 50%,#2a2e33 82%,#6a7078 100%);
      box-shadow:0 80px 160px rgba(0,0,0,.75),0 0 0 3px rgba(255,255,255,.08) inset,0 0 120px rgba(47,240,127,.12)}
    .screen{position:relative;width:962px;height:2090px;border-radius:128px;overflow:hidden;background:#000}
    .screen img{width:100%;display:block}
    .island{position:absolute;top:30px;left:50%;transform:translateX(-50%);width:276px;height:81px;border-radius:41px;background:#000}
    .glow{position:absolute;width:1000px;height:1000px;border-radius:50%;background:radial-gradient(circle, rgba(47,240,127,.30), transparent 65%);filter:blur(40px);z-index:1}
    .ribbon{position:absolute;top:0;left:0;z-index:2;${rtl ? 'transform:scaleX(-1)' : ''}}
    .chip{position:absolute;z-index:6;padding:34px 46px;border-radius:44px;min-width:420px;
      background:linear-gradient(160deg,rgba(40,48,52,.85),rgba(20,24,27,.75));backdrop-filter:blur(30px);
      border:2px solid rgba(255,255,255,.18);box-shadow:0 40px 80px rgba(0,0,0,.55),0 0 60px rgba(47,240,127,.25)}
    .chip .k{font-size:36px;color:#C9D1D6}
    .chip .v{font-family:${font};font-size:84px;font-weight:800;color:#fff;margin-top:6px;direction:ltr;text-align:${rtl ? 'right' : 'left'}}
    .big{position:absolute;top:780px;left:-60px;right:-60px;text-align:center;direction:ltr;z-index:2;white-space:nowrap;
      font-family:'Space Grotesk';font-weight:700;font-size:430px;line-height:1;letter-spacing:-18px;
      color:transparent;-webkit-text-stroke:5px rgba(47,240,127,.6);text-shadow:0 0 80px rgba(47,240,127,.25)}
    .stage{position:absolute;inset:0;perspective:3200px;z-index:3}
    .eyebrow{display:inline-flex;align-items:center;gap:18px;padding:14px 30px;margin-bottom:40px;border-radius:40px;
      font-family:'Space Grotesk';font-weight:700;font-size:38px;color:#DDE5E2;direction:ltr;
      background:rgba(47,240,127,.10);border:2px solid rgba(47,240,127,.35)}
    .eyebrow .mark{width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,${ACCENT},#38E1FF);box-shadow:0 0 24px ${ACCENT}}
    .hl{background:linear-gradient(90deg,${ACCENT},#5CF2C8 60%,#38E1FF);-webkit-background-clip:text;background-clip:text;color:transparent;
      text-shadow:none;filter:drop-shadow(0 0 30px rgba(47,240,127,.55))}
    .live{position:absolute;z-index:8;top:760px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:30px;
      padding:30px 50px;border-radius:90px;background:#000;border:2px solid rgba(255,255,255,.10);direction:ltr;
      box-shadow:0 30px 80px rgba(0,0,0,.8),0 0 70px rgba(47,240,127,.35)}
    .live .dot{width:26px;height:26px;border-radius:50%;background:${ACCENT};box-shadow:0 0 20px ${ACCENT}}
    .live .t{font-family:'Space Grotesk';font-weight:700;font-size:62px;color:#fff;font-variant-numeric:tabular-nums}
    .live .v{font-family:'Space Grotesk';font-weight:700;font-size:62px;color:${ACCENT}}
    .grain{position:absolute;inset:0;z-index:20;pointer-events:none;opacity:.08;mix-blend-mode:overlay;
      background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='300' height='300'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>")}
    .pop{position:absolute;z-index:7;overflow:hidden;border-radius:56px;border:3px solid rgba(47,240,127,.75);background:#000;
      box-shadow:0 60px 140px rgba(0,0,0,.85),0 0 90px rgba(47,240,127,.45)}
  </style></head><body>${html}</body></html>`;
  fs.writeFileSync(cfg.out + '.html', page);

  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell' });
  const tab = await browser.newPage({ viewport: { width, height: H }, deviceScaleFactor: 1 });
  await tab.goto('file://' + path.resolve(cfg.out + '.html'));
  await tab.evaluate(() => document.fonts.ready);
  const n = cfg.slides.length;
  for (let i = 0; i < n; i++) {
    const col = (cfg.style === 'panorama' || cfg.style === 'hero') && rtl ? n - 1 - i : i;
    await tab.screenshot({ path: `${cfg.out}-${i + 1}.png`, clip: { x: col * W, y: 0, width: W, height: H } });
  }
  await browser.close();
})();
