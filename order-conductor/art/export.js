// 그림을 index.html 의 ART 블록으로 내보내요:  node art/export.js
const fs = require('fs');
const path = require('path');
const { build } = require('./raster.js');
const { PAL, SPR } = require('./cast.js');
const ALPHA = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-/:;<=>?@[]^_{|}';
const colors = [], idx = {};
const out = {};
function encode(spr, g) {
  return g.map(row => {
    const chars = row.map(c => {
      if (c === '.') return '.';
      const col = ((spr.pal || {})[c] || PAL[c]).toLowerCase();
      if (!(col in idx)) { idx[col] = colors.length; colors.push(col); if (colors.length > ALPHA.length) throw new Error('too many colors'); }
      return ALPHA[idx[col]];
    });
    // 같은 칸이 4개 이상 이어지면 ~ + 글자 + 길이(36진수 2자리)로 줄여요
    let s = '';
    for (let i = 0; i < chars.length;) {
      let j = i; while (j < chars.length && chars[j] === chars[i]) j++;
      const n = j - i;
      s += n >= 4 ? '~' + chars[i] + n.toString(36).padStart(2, '0') : chars[i].repeat(n);
      i = j;
    }
    return s.replace(/(~\.[0-9a-z]{2})+$/, '').replace(/\.+$/, '');
  }).join('|');
}
for (const [name, spr] of Object.entries(SPR)) {
  const frames = [], seen = {};
  const add = pose => { const e = encode(spr, build(spr, pose)); if (!(e in seen)) { seen[e] = frames.length; frames.push(e); } return seen[e]; };
  const anims = {};
  const defs = spr.anims || { idle: { frames: [{ ms: 1000, pose: {} }] } };
  for (const [k, a] of Object.entries(defs)) anims[k] = { f: a.frames.map(fr => add(fr.pose)), ms: a.frames.map(fr => fr.ms), hit: a.hit };
  out[name] = { w: spr.w, h: spr.h, face: spr.face, enemy: !!spr.enemy, frames, anims };
}
const js = `const ART = ${JSON.stringify({ pal: colors, spr: out })};`;
const file = path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(file, 'utf8');
const A = '/* ART:BEGIN', B = '/* ART:END */';
let next;
if (html.includes(A)) {
  next = html.slice(0, html.indexOf(A)) + `${A} — art/export.js 가 만든 도트 그림이에요. 직접 고치지 말고 art/cast.js 를 고친 뒤 다시 내보내요. */\n${js}\n` + html.slice(html.indexOf(B));
} else {
  const anchor = '/* ENGINE:BEGIN';
  next = html.replace(anchor, `${A} — art/export.js 가 만든 도트 그림이에요. 직접 고치지 말고 art/cast.js 를 고친 뒤 다시 내보내요. */\n${js}\n${B}\n\n${anchor}`);
}
fs.writeFileSync(file, next);
console.log(`exported ${Object.keys(out).length} sprites, ${colors.length} colors, ${js.length} bytes`);
