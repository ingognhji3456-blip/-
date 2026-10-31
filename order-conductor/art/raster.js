// 도트 캔버스: 모양으로 윤곽을 잡고(ops), 한 칸씩 덧칠(rows), 마지막에 재료별 색으로 1칸 외곽선.
//  ops: ['E',cx,cy,rx,ry,c] 타원, ['R',x,y,w,h,c] 사각형, ['P',[[x,y]...],c] 다각형, ['L',x0,y0,x1,y1,굵기,c] 선,
//       ['B',x0,y0,x1,y1,c] 1칸 선, ['re',from,to,모양] 모양 안의 from 색을 to로, ['ro',from,to,모양] 모양 밖, ['X',모양] 지우기
//       ['@','부위'] 이 뒤의 ops 는 그 부위 (['@', null] 로 끝)
//  rows[y]: 'x:RLE ...' (예: '12:B3k1' = 12번 칸부터 B 3칸, k 1칸). '.'은 건너뛰기, '_'는 지우기.
//  pose (애니메이션 한 칸):
//    parts: { 부위: { rot(도), px, py(돌리는 중심), dx, dy } }  — 부위를 돌리고 옮겨요
//    pull:  { dx, dy }  — 'string' 부위의 1칸 선은 끝점(두 번째 점)만 이만큼 따라가요 (활시위)
//    hide:  ['부위', …]  — 그 부위를 안 그려요
//    extra: [ops…]      — 이 칸에만 덧그려요
//    breath: n          — 허리(waist) 위쪽을 n칸 아래로 (숨쉬기)
//    lean: n            — 허리 위쪽을 n칸 옆으로 (젖히기/숙이기)
function inShape(sh, x, y) {
  const px = x + 0.5, py = y + 0.5;
  if (sh[0] === 'E') { const [, cx, cy, rx, ry] = sh; return ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1; }
  if (sh[0] === 'R') { const [, x0, y0, w, h] = sh; return x >= x0 && x < x0 + w && y >= y0 && y < y0 + h; }
  if (sh[0] === 'P') { const pts = sh[1]; let ins = false; for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) { const [xi, yi] = pts[i], [xj, yj] = pts[j]; if ((yi > py) !== (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) ins = !ins; } return ins; }
  if (sh[0] === 'L') { const [, x0, y0, x1, y1, w] = sh; const dx = x1 - x0, dy = y1 - y0; const t = Math.max(0, Math.min(1, ((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy || 1))); const qx = x0 + t * dx, qy = y0 + t * dy; return (px - qx) ** 2 + (py - qy) ** 2 <= (w / 2) ** 2; }
  throw new Error('bad shape ' + sh[0]);
}
function pt(x, y, t) {
  let X = x, Y = y;
  if (t.rot) { const a = t.rot * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), dx = x - (t.px || 0), dy = y - (t.py || 0); X = (t.px || 0) + dx * c - dy * s; Y = (t.py || 0) + dx * s + dy * c; }
  return [X + (t.dx || 0), Y + (t.dy || 0)];
}
function moveShape(sh, t) {
  if (sh[0] === 'E') { const [x, y] = pt(sh[1], sh[2], t); return ['E', x, y, sh[3], sh[4]]; }
  if (sh[0] === 'R') {
    if (!t.rot) return ['R', sh[1] + (t.dx || 0), sh[2] + (t.dy || 0), sh[3], sh[4]];
    const [, x, y, w, h] = sh; return ['P', [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map(p => pt(p[0], p[1], t))];
  }
  if (sh[0] === 'P') return ['P', sh[1].map(p => pt(p[0], p[1], t))];
  if (sh[0] === 'L') { const a = pt(sh[1], sh[2], t), b = pt(sh[3], sh[4], t); return ['L', a[0], a[1], b[0], b[1], sh[5]]; }
  return sh;
}
function moveOp(op, t, pullOnly) {
  const k = op[0];
  if (k === 're' || k === 'ro') return [k, op[1], op[2], moveShape(op[3], t)];
  if (k === 'X') return ['X', moveShape(op[1], t)];
  if (k === 'B') {
    const a = pullOnly ? [op[1], op[2]] : pt(op[1], op[2], t), b = pt(op[3], op[4], t);
    return ['B', Math.round(a[0]), Math.round(a[1]), Math.round(b[0]), Math.round(b[1]), op[5]];
  }
  const c = op[op.length - 1];
  return moveShape(op.slice(0, -1), t).concat([c]);
}
function poseOps(spr, pose) {
  const out = []; let part = null;
  const P = (pose && pose.parts) || {}, hide = new Set((pose && pose.hide) || []);
  for (const op of spr.ops || []) {
    if (op[0] === '@') { part = op[1]; continue; }
    if (part && hide.has(part)) continue;
    if (part === 'string' && pose && pose.pull) { out.push(moveOp(op, pose.pull, true)); continue; }
    const t = part && P[part];
    out.push(t ? moveOp(op, t, false) : op);
  }
  return out.concat((pose && pose.extra) || []);
}
function build(spr, pose) {
  const W = spr.w, H = spr.h;
  const g = Array.from({ length: H }, () => Array(W).fill('.'));
  for (const op of poseOps(spr, pose)) {
    const kind = op[0];
    if (kind === 're' || kind === 'ro') {
      const [, from, to, sh] = op;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const c = g[y][x]; if (c === '.') continue;
        if (from !== '*' && !from.includes(c)) continue;
        if (inShape(sh, x, y) === (kind === 're')) g[y][x] = to;
      }
    } else if (kind === 'B') {
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
  // 숨쉬기·젖히기: 허리 위쪽 칸들을 옮겨요
  const waist = spr.waist || Math.floor(H * 0.6);
  const by = (pose && pose.breath) || 0, lx = (pose && pose.lean) || 0;
  if (by || lx) {
    const top = g.slice(0, waist).map(r => r.slice());
    for (let y = 0; y < waist; y++) g[y] = Array(W).fill('.');
    for (let y = 0; y < waist; y++) for (let x = 0; x < W; x++) {
      const c = top[y][x]; if (c === '.') continue;
      const ny = y + by, nx = x + lx;
      if (ny >= 0 && ny < H && nx >= 0 && nx < W) g[ny][nx] = c;
    }
    // 아래로 내린 만큼 허리 바로 위 빈 줄은 위 칸으로 채워요 (몸이 끊어지지 않게)
    if (by < 0) for (let k = 0; k < -by; k++) { const y = waist - 1 - k; if (y >= 0) for (let x = 0; x < W; x++) if (g[y][x] === '.' && g[waist] && g[waist][x] !== '.') g[y][x] = g[waist][x]; }
  }
  if (spr.dy) { for (let k = 0; k < spr.dy; k++) { g.pop(); g.unshift(Array(W).fill('.')); } }
  const out = g.map(r => r.slice());
  const OL = spr.outline || {};
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (g[y][x] !== '.') continue;
    let best = null;
    for (const [dx, dy] of [[0, -1], [-1, 0], [1, 0], [0, 1]]) { const v = (g[y + dy] || [])[x + dx]; if (v && v !== '.' && !'123456789'.includes(v) && !((spr.bare || '') + '^').includes(v)) best = v; }
    if (best) out[y][x] = OL[best] || '1';
  }
  return out;
}
if (typeof module !== 'undefined') module.exports = { build };
