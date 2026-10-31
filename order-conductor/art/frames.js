// 애니메이션 미리보기: node frames.js out.png 이름 [동작...]  (칸마다 3배, 아래는 실제 크기)
const { createRequire } = require('module');
const req = createRequire(__filename);
let chromium; try { ({ chromium } = req('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const { build } = require('./raster.js');
const { PAL, SPR } = require('./cast.js');
function svg(name, pose, scale) {
  const spr = SPR[name], g = build(spr, pose), H = g.length, W = g[0].length; let r = '';
  g.forEach((row, y) => row.forEach((c, x) => { if (c !== '.') r += `<rect x="${x}" y="${y}" width="1.03" height="1.03" fill="${(spr.pal || {})[c] || PAL[c] || '#f0f'}"/>`; }));
  return `<svg width="${W * scale}" height="${H * scale}" viewBox="0 0 ${W} ${H}" shape-rendering="crispEdges" style="background:#7d8fbf">${r}</svg>`;
}
const out = process.argv[2], name = process.argv[3], which = process.argv.slice(4);
const anims = SPR[name].anims;
const html = `<body style="margin:0;padding:10px;background:#121a33;color:#fff;font:13px sans-serif">${Object.entries(anims).filter(([k]) => !which.length || which.includes(k)).map(([k, a]) =>
  `<div style="margin-bottom:8px">${k}${a.hit !== undefined ? ` (맞는 칸 ${a.hit + 1})` : ''}<div style="display:flex;gap:6px;align-items:flex-end">${a.frames.map((f, i) => `<div style="text-align:center">${svg(name, f.pose, +(process.env.Z || 3))}<div>${i + 1} · ${f.ms}ms</div></div>`).join('')}</div></div>`).join('')}</body>`;
(async () => { const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1700, height: 300 } }); await p.setContent(html); await p.screenshot({ path: out, fullPage: true }); await b.close(); })();
