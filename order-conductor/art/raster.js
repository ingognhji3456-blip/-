// 도트 캔버스: 모양으로 윤곽을 잡고(ops), 한 칸씩 덧칠(rows), 마지막에 재료별 색으로 1칸 외곽선.
//  ops: ['E',cx,cy,rx,ry,c] 타원, ['R',x,y,w,h,c] 사각형, ['P',[[x,y]...],c] 다각형, ['L',x0,y0,x1,y1,굵기,c] 선,
//       ['re',from,to,모양] 모양 안의 from 색을 to로, ['ro',from,to,모양] 모양 밖, ['X',모양] 지우기
//  rows[y]: 'x:RLE ...' (예: '12:B3k1' = 12번 칸부터 B 3칸, k 1칸). '.'은 건너뛰기, '_'는 지우기.
function inShape(sh, x, y) {
  const px = x + 0.5, py = y + 0.5;
  if (sh[0] === 'E') { const [, cx, cy, rx, ry] = sh; return ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1; }
  if (sh[0] === 'R') { const [, x0, y0, w, h] = sh; return x >= x0 && x < x0 + w && y >= y0 && y < y0 + h; }
  if (sh[0] === 'P') { const pts = sh[1]; let ins = false; for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) { const [xi, yi] = pts[i], [xj, yj] = pts[j]; if ((yi > py) !== (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) ins = !ins; } return ins; }
  if (sh[0] === 'L') { const [, x0, y0, x1, y1, w] = sh; const dx = x1 - x0, dy = y1 - y0; const t = Math.max(0, Math.min(1, ((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy || 1))); const qx = x0 + t * dx, qy = y0 + t * dy; return (px - qx) ** 2 + (py - qy) ** 2 <= (w / 2) ** 2; }
  throw new Error('bad shape ' + sh[0]);
}
function build(spr) {
  const W = spr.w, H = spr.h;
  const g = Array.from({ length: H }, () => Array(W).fill('.'));
  for (const op of spr.ops || []) {
    const kind = op[0];
    if (kind === 're' || kind === 'ro') {
      const [, from, to, sh] = op;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const c = g[y][x]; if (c === '.') continue;
        if (from !== '*' && !from.includes(c)) continue;
        if (inShape(sh, x, y) === (kind === 're')) g[y][x] = to;
      }
    } else if (kind === 'B') {                        // 1칸짜리 곧은 선: ['B',x0,y0,x1,y1,c]
      let [, x0, y0, x1, y1, c] = op; const dx = Math.abs(x1 - x0), sx = x0 < x1 ? 1 : -1, dy = -Math.abs(y1 - y0), sy = y0 < y1 ? 1 : -1; let err = dx + dy;
      for (;;) { if (y0 >= 0 && y0 < H && x0 >= 0 && x0 < W) g[y0][x0] = c; if (x0 === x1 && y0 === y1) break; const e2 = 2 * err; if (e2 >= dy) { err += dy; x0 += sx; } if (e2 <= dx) { err += dx; y0 += sy; } }
    } else if (kind === 'X') {
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (inShape(op[1], x, y)) g[y][x] = '.';
    } else {
      const c = op[op.length - 1], sh = op.slice(0, -1);
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (inShape(sh, x, y)) g[y][x] = c;
    }
  }
  (spr.rows || []).forEach((row, y) => {
    if (!row) return;
    for (const seg of row.trim().split(/\s+/)) {
      const [xs, px] = seg.split(':'); let x = +xs;
      const re = /(.)(\d*)/g; let m;
      while ((m = re.exec(px)) && m[0]) { const ch = m[1], n = m[2] ? +m[2] : 1; for (let i = 0; i < n; i++) { if (ch === '_') g[y][x] = '.'; else if (ch !== '.') g[y][x] = ch; x++; } }
    }
  });
  if (spr.dy) { for (let k = 0; k < spr.dy; k++) { g.pop(); g.unshift(Array(W).fill('.')); } }
  const out = g.map(r => r.slice());
  const OL = spr.outline || {};
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (g[y][x] !== '.') continue;
    let best = null;
    for (const [dx, dy] of [[0, -1], [-1, 0], [1, 0], [0, 1]]) { const v = (g[y + dy] || [])[x + dx]; if (v && v !== '.' && !'123456789'.includes(v) && !(spr.bare || '').includes(v)) best = v; }
    if (best) out[y][x] = OL[best] || '1';
  }
  return out;
}
if (typeof module !== 'undefined') module.exports = { build };
