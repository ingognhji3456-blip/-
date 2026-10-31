// 미리보기: node show.js out.png 이름... (무대 배경 위 4배 + 2배 + 실제 크기, 확대 격자 보기는 GRID=1)
const { createRequire } = require('module');
const req = createRequire(__filename);
let chromium; try { ({ chromium } = req('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const { build } = require('./raster.js');
const { PAL, SPR } = require('./cast.js');
function svg(name, scale, flip, grid) {
  const spr = SPR[name], g = build(spr), H = g.length, W = g[0].length; let r = '';
  g.forEach((row, y) => row.forEach((c, x) => { if (c !== '.') r += `<rect x="${x}" y="${y}" width="1.03" height="1.03" fill="${(spr.pal || {})[c] || PAL[c] || '#f0f'}"/>`; }));
  let gl = '';
  if (grid) { for (let i = 0; i <= W; i += 4) gl += `<line x1="${i}" y1="0" x2="${i}" y2="${H}" stroke="${i % 16 ? '#ffffff22' : '#ffffff55'}" stroke-width=".06"/>`; for (let i = 0; i <= H; i += 4) gl += `<line x1="0" y1="${i}" x2="${W}" y2="${i}" stroke="${i % 16 ? '#ffffff22' : '#ffffff55'}" stroke-width=".06"/>`; }
  return `<svg width="${W * scale}" height="${H * scale}" viewBox="0 0 ${W} ${H}" shape-rendering="crispEdges">${flip ? `<g transform="translate(${W} 0) scale(-1 1)">${r}</g>` : r}${gl}</svg>`;
}
const out = process.argv[2]; const names = process.argv.slice(3).length ? process.argv.slice(3) : Object.keys(SPR);
const big = +(process.env.BIG || 4), grid = !!process.env.GRID;
const html = `<body style="margin:0;padding:0;background:#121a33">
<div style="display:flex;align-items:flex-end;gap:16px;padding:16px 20px 0;background:${grid ? '#8fa0c8' : 'linear-gradient(180deg,#1d2a5c 0%,#3b3770 60%,#7a5a80 100%)'}">
${names.map(n => svg(n, big, !grid && SPR[n].enemy, grid)).join('')}
</div>
<div style="height:20px;background:linear-gradient(#5c8a48 0 4px,#3f5f33 4px 8px,#3a3226 8px)"></div>
<div style="display:flex;align-items:flex-end;gap:6px;padding:10px 20px 6px;background:#2a3566">${names.map(n => svg(n, 1.5, SPR[n].enemy)).join('')}<span style="width:30px"></span>${names.map(n => svg(n, 1, SPR[n].enemy)).join('')}</div>
</body>`;
(async () => { const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1500, height: 400 } }); await p.setContent(html); await p.screenshot({ path: out, fullPage: true }); await b.close(); })();
