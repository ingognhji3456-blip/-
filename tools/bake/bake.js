// hunter.html(웹 프로토타입)의 그림·소리 코드를 그대로 돌려서 Godot용 에셋을 만들어요.
// 사용법: node tools/bake/bake.js [creatures|hero|props|bg|terrain|audio|data|all]
// 필요: playwright(크로미움), ffmpeg(libvorbis)
const path = require('path'), fs = require('fs'), { execFileSync } = require('child_process');
let chromium; try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const ROOT = path.resolve(__dirname, '../..'), OUT = path.join(ROOT, 'godot/assets'), TMP = fs.mkdtempSync('/tmp/bake-');
const what = process.argv[2] || 'all';
const mk = d => { fs.mkdirSync(path.join(OUT, d), { recursive: true }); return path.join(OUT, d); };
const savePng = (file, dataUrl) => fs.writeFileSync(file, Buffer.from(dataUrl.split(',')[1], 'base64'));
const saveJson = (file, obj) => fs.writeFileSync(file, JSON.stringify(obj, null, 1));
function saveOgg(file, b64, q = 4) {
  const wav = path.join(TMP, path.basename(file) + '.wav'); fs.writeFileSync(wav, Buffer.from(b64, 'base64'));
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', String(q), file]); fs.unlinkSync(wav);
}

(async () => {
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto('file://' + path.join(ROOT, 'hunter.html'));
  await page.evaluate(() => {
    update = () => {}; render = () => {}; updateHud = () => {};
    window.BK = { label: label, shadow: shadow };
    window.toURL = c => c.toDataURL('image/png');
    window.cnv = (w, h) => { const c = document.createElement('canvas'); c.width = Math.ceil(w); c.height = Math.ceil(h); return c; };
  });
  const all = what === 'all';

  if (all || what === 'creatures') {
    const dir = mk('creatures'), meta = {};
    const types = ['slime', 'rabbit', 'wolf', 'boar', 'bat', 'golem', 'wisp', 'yeti', 'scorp', 'worm', 'toad', 'lizard', 'dragon'];
    for (const type of types) {
      const r = await page.evaluate((type) => {
        DPR = 1; const ps = type === 'dragon' ? 1.7 : 2.5;
        const S = [['idle', 8, i => ({ t: i / 8 * 3 })], ['walk', 8, i => ({ speed: 'walk', ph: i / 8 * 6.2832, t: i / 8 })], ['run', 8, i => ({ speed: 'run', ph: i / 8 * 6.2832, t: i / 8 * .6, angry: true })],
          ['ready', 8, i => ({ ready: true, angry: true, t: i / 8 * 3 })], ['wind', 5, i => ({ ready: true, angry: true, wind: (i + 1) / 5 })],
          ['lunge', 6, i => ({ angry: true, lunge: [.3, .65, .9, 1, .6, .25][i] })], ['hurt', 3, i => ({ ready: true, hurt: [.4, .8, 1][i] })],
          ['dead', 10, i => ({ dead: ease(i / 9), ko: i >= 2 })]];
        if (type === 'worm') S.push(['burrow', 4, i => ({ speed: 'walk', burrow: 0, t: i / 4 })], ['emerge', 6, i => ({ burrow: (i + 1) / 6, angry: true })]);
        const fw = Math.ceil((CREA_W[type] * 1.4 + 50) * ps), fh = Math.ceil((CREA_H[type] * 1.45 + 30) * ps);
        const n = S.reduce((a, s) => a + s[1], 0), cols = 8, rows = Math.ceil(n / cols);
        const sheet = cnv(fw * cols, fh * rows), g = sheet.getContext('2d'), states = {};
        let idx = 0; const keep = ctx;
        for (const [name, cnt, f] of S) {
          states[name] = { start: idx, count: cnt };
          for (let i = 0; i < cnt; i++, idx++) {
            const st = Object.assign({ t: 0, ph: 0, speed: 'idle', wind: 0, lunge: 0, hurt: 0, graze: 0, var: 0, lod: 1, burrow: 1 }, f(i));
            const cx = (idx % cols) * fw, cy = Math.floor(idx / cols) * fh;
            ctx = g; g.setTransform(1, 0, 0, 1, 0, 0); g.save(); g.beginPath(); g.rect(cx, cy, fw, fh); g.clip();
            drawCreatureOn(type, st, cx + fw / 2, cy + fh - 12 * ps, ps, 1, 1, { rim: 'rgba(16,12,10,.5)', rimW: 1.3 });
            g.restore(); ctx = keep;
          }
        }
        return { url: toURL(sheet), meta: { fw, fh, cols, ps, ox: fw / 2, oy: fh - 12 * ps, height: CREA_H[type], width: CREA_W[type], states } };
      }, type);
      savePng(path.join(dir, type + '.png'), r.url); meta[type] = r.meta; console.log('creature', type, r.meta.fw + 'x' + r.meta.fh);
    }
    saveJson(path.join(dir, 'creatures.json'), meta);
  }

  if (all || what === 'hero') {
    const dir = mk('hero');
    const r = await page.evaluate(() => {
      DPR = 1; shadow = () => {}; const out = {};
      // 필드용: 아래·위·옆 걷기/서기, 옆 휘두르기
      { const ps = 3, fw = 64 * ps, fh = 72 * ps, ax = 32 * ps, ay = 62 * ps, S = [];
        for (const v of ['down', 'up', 'side']) { S.push([v + '_idle', 4, i => ({ view: v, moving: false, t: i / 4 * 2.6 })]); S.push([v + '_walk', 8, i => ({ view: v, moving: true, anim: i / 8 * 6.2832, t: i / 8 })]); }
        S.push(['side_swing', 6, i => ({ view: 'side', moving: false, swing: .22 * (1 - i / 6), t: 0 })]);
        const n = S.reduce((a, s) => a + s[1], 0), cols = 8, sheet = cnv(fw * cols, fh * Math.ceil(n / cols)), g = sheet.getContext('2d'), states = {};
        const keep = ctx, kp = { x: P.x, y: P.y, view: P.view, moving: P.moving, anim: P.anim, swing: P.swing, hurt: P.hurt, face: P.face }, pet = ST.pet; ST.pet = 0;
        let idx = 0;
        for (const [name, cnt, f] of S) { states[name] = { start: idx, count: cnt }; for (let i = 0; i < cnt; i++, idx++) {
          const o = f(i); P.x = 0; P.y = 0; P.view = o.view; P.moving = o.moving; P.anim = o.anim || 0; P.swing = o.swing || 0; P.hurt = 0; P.face = 1;
          const cx = (idx % cols) * fw, cy = Math.floor(idx / cols) * fh;
          ctx = g; g.setTransform(1, 0, 0, 1, 0, 0); g.save(); g.beginPath(); g.rect(cx, cy, fw, fh); g.clip(); g.translate(cx + ax, cy + ay); g.scale(ps, ps); drawPlayer(o.t); g.restore(); ctx = keep;
        } }
        Object.assign(P, kp); ST.pet = pet;
        out.world = { url: toURL(sheet), meta: { fw, fh, cols, ps, ox: ax, oy: ay, states } };
      }
      // 전투용: 동작마다 프레임 + 앞으로 뛰어드는 거리(dx)와 칼끝 위치
      { const ps = 2.4, fw = 110 * ps, fh = 100 * ps, ax = 50 * ps, ay = 82 * ps;
        const M = [['idle', 8, .5], ['slashDown', 10, .32], ['slashUp', 10, .32], ['thrust', 10, .32], ['spin', 12, .32], ['riposte', 8, .3], ['whiff', 8, .26], ['finisher', 14, .5], ['flurry', 8, 0], ['hurt', 8, .4], ['stumble', 8, .4], ['block', 1, 0], ['dead', 10, 0]];
        const n = M.reduce((a, s) => a + s[1], 0), cols = 8, sheet = cnv(fw * cols, fh * Math.ceil(n / cols)), g = sheet.getContext('2d'), states = {};
        const keep = ctx, keepC = C; let idx = 0;
        for (const [name, cnt, dur] of M) {
          states[name] = { start: idx, count: cnt, dur, frames: [] };
          for (let i = 0; i < cnt; i++, idx++) {
            let o, pd = 0;
            if (name === 'idle' || name === 'dead') { C = { pAct: null, vis: 0, pBlock: 0 }; o = heroPose(); if (name === 'idle') o.bob = -Math.sin(i / cnt * 6.2832) * .8; else pd = ease(i / (cnt - 1)); }
            else if (name === 'block') { C = { pAct: null, vis: 0, pBlock: 1 }; o = heroPose(); }
            else if (name === 'flurry') { C = { pAct: { move: 'flurry', t0: 0, dur: 99 }, vis: i / cnt * (6.2832 / 30), holding: true, pBlock: 0 }; o = heroPose(); }
            else { C = { pAct: { move: name, t0: 0, dur }, vis: i / cnt * dur * .999, pBlock: 0 }; o = heroPose(); }
            const cx = (idx % cols) * fw, cy = Math.floor(idx / cols) * fh;
            ctx = g; g.setTransform(1, 0, 0, 1, 0, 0); g.save(); g.beginPath(); g.rect(cx, cy, fw, fh); g.clip(); g.translate(cx + ax, cy + ay);
            if (pd) { g.translate(0, pd * 6); g.rotate(-pd * .35); }
            g.scale(ps, ps); if (o.rot) { g.translate(0, -26); g.rotate(o.rot); g.translate(0, 26); }
            hunterSide({ bob: o.bob + (pd ? -pd * 8 : 0), la: o.la * (1 - pd) + pd * .9, ba: o.ba, aa: pd ? lerp(o.aa, .8, pd) : o.aa, sr: o.sr, flap: 2 + o.dx * 4, blink: false, ouch: o.ouch || pd > .2, fierce: true, yell: o.yell, lean: o.lean + pd * .7 });
            g.restore(); ctx = keep;
            const tip = swordTip(o, 0, 0, 1);
            states[name].frames.push({ dx: +o.dx.toFixed(3), dy: +o.dy.toFixed(2), tip: [+tip[0].toFixed(1), +tip[1].toFixed(1)], strike: !!o.strike });
          }
        }
        C = keepC;
        out.battle = { url: toURL(sheet), meta: { fw, fh, cols, ps, ox: ax, oy: ay, states } };
      }
      return out;
    });
    savePng(path.join(dir, 'hero_world.png'), r.world.url); savePng(path.join(dir, 'hero_battle.png'), r.battle.url);
    saveJson(path.join(dir, 'hero.json'), { world: r.world.meta, battle: r.battle.meta }); console.log('hero ok');
  }

  if (all || what === 'props') {
    const dir = mk('props');
    const r = await page.evaluate(() => {
      DPR = 1; const out = {}, meta = {};
      for (const k in SPR) { const s = SPR[k]; out[k] = toURL(s.c); meta[k] = { w: s.w, h: s.h, ax: s.ax, ay: s.ay, scale: SS }; }
      // 건물과 분수
      label = () => {}; const keep = ctx, kp = { x: P.x, y: P.y }; P.x = -9999; P.y = -9999;
      for (const b of BLD) { const ps = 2, c = cnv(200 * ps, 170 * ps), g = c.getContext('2d'); ctx = g; g.scale(ps, ps); g.translate(100 - b.x, 110 - b.y); drawBuilding(b, 0); ctx = keep; out['bld_' + b.id] = toURL(c); meta['bld_' + b.id] = { w: 200, h: 170, ax: 100, ay: 110, scale: ps }; }
      { const ps = 2, c = cnv(100 * ps, 80 * ps), g = c.getContext('2d'); ctx = g; g.scale(ps, ps); g.translate(50 - CX, 50 - CY); drawFountain(0); ctx = keep; out.fountain = toURL(c); meta.fountain = { w: 100, h: 80, ax: 50, ay: 50, scale: ps }; }
      label = BK.label; Object.assign(P, kp);
      return { out, meta };
    });
    for (const k in r.out) savePng(path.join(dir, k + '.png'), r.out[k]);
    saveJson(path.join(dir, 'props.json'), r.meta); console.log('props', Object.keys(r.out).length);
  }

  if (all || what === 'bg') {
    const dir = mk('bg');
    for (let z = 1; z <= 7; z++) {
      const url = await page.evaluate((z) => { DPR = 1; return toURL(battleBg(z, 1600, 640, 548)); }, z);
      savePng(path.join(dir, 'battle_' + z + '.png'), url); console.log('bg', z);
    }
    saveJson(path.join(dir, 'bg.json'), { w: 1600, h: 640, ground: 548 });
  }

  if (all || what === 'terrain') {
    const dir = mk('terrain');
    const r = await page.evaluate(() => {
      const N = 1000, s = WORLD / N, col = cnv(N, N), info = cnv(N, N), cg = col.getContext('2d'), ig = info.getContext('2d');
      const ci = cg.createImageData(N, N), ii = ig.createImageData(N, N), o = [0, 0, 0];
      for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
        const x = (i + .5) * s, y = (j + .5) * s, k = (j * N + i) * 4; groundColor(x, y, o);
        ci.data[k] = o[0]; ci.data[k + 1] = o[1]; ci.data[k + 2] = o[2]; ci.data[k + 3] = 255;
        const zd = warpD(x, y), z = zoneAtD(x, y, zd), v = lakeV(x, y, zd, z);
        ii.data[k] = z * 32; ii.data[k + 1] = v > 0 ? (z === 4 ? 128 : 255) : 0; ii.data[k + 2] = roadDist(x, y) < roadHalf(x, y) ? 255 : 0; ii.data[k + 3] = 255;
      }
      cg.putImageData(ci, 0, 0); ig.putImageData(ii, 0, 0);
      const wg = cnv(WN, WN), wgc = wg.getContext('2d'), wi = wgc.createImageData(WN, WN);
      for (let i = 0; i < WN * WN; i++) { wi.data[i * 4] = waterGrid[i] ? 255 : 0; wi.data[i * 4 + 3] = 255; }
      wgc.putImageData(wi, 0, 0);
      // 지역마다 이어 붙여도 티 안 나는 바닥 무늬
      const det = {};
      for (let z = 0; z <= 6; z++) {
        const T = 256, c = cnv(T, T), g = c.getContext('2d'), R = mulberry(SEED + 50 + z);
        for (let n = 0; n < 150; n++) {
          const lx = R() * T, ly = R() * T, r = R(), r2 = R();
          for (const [dx, dy] of [[0, 0], [-T, 0], [0, -T], [-T, -T]]) {
            const x = lx + dx + (lx < 20 ? T : 0) * 0, y = ly + dy;
            g.save(); g.translate(dx === 0 && lx > T - 20 ? -T : 0, dy === 0 && ly > T - 20 ? -T : 0);
            const RR = mulberry(n * 977 + z);
            if (z <= 1 || z === 2 || z === 6) { if (r < .7) grassTuft(g, RR, lx + dx, ly + dy, 4 + Math.floor(r2 * 4), q => z === 1 || z === 0 ? `rgb(${50 + q * 40},${100 + q * 60},${36 + q * 24})` : z === 2 ? `rgb(${30 + q * 25},${70 + q * 40},${30 + q * 20})` : `rgb(${60 + q * 30},${80 + q * 30},${36 + q * 10})`); else if (z === 1 && r < .9) { g.fillStyle = ['#ffffff', '#ffe066', '#c9a2ff', '#ff8fa8'][Math.floor(r2 * 4)]; for (let p = 0; p < 5; p++) { const a = p * 1.2566; g.beginPath(); g.arc(lx + dx + Math.cos(a) * 1.5, ly + dy + Math.sin(a) * 1.5, 1.2, 0, 6.283); g.fill(); } } else if (z === 2) { g.fillStyle = ['#8a5a2a', '#a8742e', '#6b4a24'][Math.floor(r2 * 3)]; g.beginPath(); g.ellipse(lx + dx, ly + dy, 2.6, 1.3, r2 * 6, 0, 6.283); g.fill(); } }
            else if (z === 3 || z === 5) { const s2 = 1.5 + r2 * 3; g.fillStyle = 'rgba(0,0,0,.22)'; g.beginPath(); g.ellipse(lx + dx + 1, ly + dy + 1, s2, s2 * .7, 0, 0, 6.283); g.fill(); g.fillStyle = z === 3 ? (r2 < .5 ? '#9b958a' : '#77716a') : (r2 < .5 ? '#b08a5a' : '#8a6a44'); g.beginPath(); g.ellipse(lx + dx, ly + dy, s2, s2 * .7, r2 * 3, 0, 6.283); g.fill(); }
            else if (z === 4) { if (r < .5) { g.fillStyle = 'rgba(255,255,255,.85)'; g.beginPath(); g.ellipse(lx + dx, ly + dy, 6 + r2 * 8, 2 + r2 * 2, 0, 0, 6.283); g.fill(); } else grassTuft(g, RR, lx + dx, ly + dy, 3, () => '#b9b08a'); }
            g.restore(); void x; void y;
          }
        }
        det[z] = toURL(c);
      }
      return { col: toURL(col), info: toURL(info), water: toURL(wg), det, WN, WG };
    });
    savePng(path.join(dir, 'color.png'), r.col); savePng(path.join(dir, 'info.png'), r.info); savePng(path.join(dir, 'water.png'), r.water);
    for (const z in r.det) savePng(path.join(dir, 'detail_' + z + '.png'), r.det[z]);
    console.log('terrain ok');
  }

  if (all || what === 'data') {
    const dir = mk('data');
    const d = await page.evaluate(() => {
      const songs = {}, idx = Object.keys(SONGS);
      for (const k of idx) {
        const S = SONGS[k], stepDur = 60 / S.bpm / 4, chart = (rage) => {
          C = { song: S, songIdx: idx.indexOf(k), stepDur, barDur: 0, beat: stepDur * 4, notes: [], sigs: [], phase2: rage };
          const bars = [];
          for (let b = 0; b < 32; b++) {
            C.notes = []; C.sigs = []; chartBar(b);
            const b0 = b * S.spb * stepDur;
            bars.push({ n: C.notes.map(n => ({ k: n.k, t: +(n.t - b0).toFixed(4), e: n.end ? +(n.end - b0).toFixed(4) : undefined, f: n.pitch ? +n.pitch.toFixed(1) : undefined })), s: C.sigs.map(q => ({ t: +(q.t - b0).toFixed(4), lead: +q.lead.toFixed(4), heavy: q.heavy })) });
          }
          return bars;
        };
        songs[k] = { title: S.title, bpm: S.bpm, spb: S.spb, loopBars: S.bars.length, normal: chart(false), rage: chart(true) };
      }
      C = null;
      const nodes2 = nodes.map(n => [n.type, n.v, Math.round(n.x), Math.round(n.y)]), decos = [];
      for (const cell of decoGrid) for (const o of cell) decos.push([o.k, Math.round(o.x), Math.round(o.y)]);
      return { world: { size: WORLD, cx: CX, cy: CY, zr: ZR, deep: DEEP, lair: LAIR, zoneNames: ZNAME, buildings: BLD.map(b => ({ id: b.id, n: b.n, x: b.x, y: b.y })), nodes: nodes2, decos }, mats: MATS, nodeTypes: NODE, monsters: MON, spawn: MON_SPAWN, upgrades: Object.fromEntries(Object.entries(UPG).map(([k, u]) => [k, { n: u.n, i: u.i, max: u.max, cost: Array.from({ length: u.max }, (_, L) => u.cost(L)) }])), songs };
    });
    saveJson(path.join(dir, 'game.json'), d); console.log('data ok', (fs.statSync(path.join(dir, 'game.json')).size / 1024 | 0) + 'KB');
  }

  if (all || what === 'audio') {
    const sdir = mk('audio/songs'), fdir = mk('audio/sfx');
    await page.evaluate(() => {
      window.wav = (buf, a, b) => {
        const sr = buf.sampleRate, s0 = Math.floor(a * sr), s1 = Math.min(buf.length, Math.floor(b * sr)), ch = buf.numberOfChannels, n = s1 - s0;
        const out = new DataView(new ArrayBuffer(44 + n * ch * 2)), ws = (o, s) => { for (let i = 0; i < s.length; i++) out.setUint8(o + i, s.charCodeAt(i)); };
        ws(0, 'RIFF'); out.setUint32(4, 36 + n * ch * 2, true); ws(8, 'WAVE'); ws(12, 'fmt '); out.setUint32(16, 16, true); out.setUint16(20, 1, true); out.setUint16(22, ch, true);
        out.setUint32(24, sr, true); out.setUint32(28, sr * ch * 2, true); out.setUint16(32, ch * 2, true); out.setUint16(34, 16, true); ws(36, 'data'); out.setUint32(40, n * ch * 2, true);
        const d = []; for (let c = 0; c < ch; c++) d.push(buf.getChannelData(c));
        let p = 44; for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) { out.setInt16(p, Math.max(-1, Math.min(1, d[c][s0 + i])) * 32767, true); p += 2; }
        const u8 = new Uint8Array(out.buffer); let s = ''; for (let i = 0; i < u8.length; i += 32768) s += String.fromCharCode.apply(null, u8.subarray(i, i + 32768)); return btoa(s);
      };
      window.offline = (sec) => { const off = new OfflineAudioContext(2, Math.ceil(32000 * sec), 32000); AC = off; MUS = null; ac = () => AC; S.sound = true; MB = openBus(.85); return off; };
    });
    for (const k of await page.evaluate(() => Object.keys(SONGS))) {
      for (const rage of [false, true]) {
        const b64 = await page.evaluate(async ([k, rage]) => {
          const S = SONGS[k], sd = 60 / S.bpm / 4, bars = S.bars.length, loop = bars * S.spb * sd, off = offline(loop * 2 + 1.5);
          const T = g => g * sd + (((g % S.spb) % 4) === 2 ? (S.swing || 0) * sd : 0);
          for (let g = 0; g < bars * S.spb * 2; g++) {
            const bar = Math.floor(g / S.spb), s = g % S.spb, t = T(g);
            if (rage) { if (s % 4 === 0) DRUM.k(t, .75); if (s % 2 === 1) DRUM.h(t, .7); if (s === 0) DRUM.X(t, .5); if (s % 8 === 6) DRUM.s(t, .5); continue; }
            for (const d in S.drums) { const c = S.drums[d][s]; if (c && c !== '.') DRUM[d](t, s === 0 ? 1 : .8); }
            const ch = chordOf(S, bar), bt = S.bassPat[s];
            if (bt && bt !== '.' && bt !== '-') { const n = bt === '1' ? ch[0] : bt === '3' ? ch[1] : bt === '5' ? ch[2] : bt === '6' ? ch[0] + 9 : ch[0] + 12; let gap = 1; while (s + gap < S.spb && S.bassPat[s + gap] === '.') gap++; BASS[S.bass](midiF(n - 12), t, Math.min(4, gap) * sd * .9); }
            if (S.pad && s === 0) PAD[S.pad](ch.map(midiF), t, S.spb * sd * .96);
            if (S.arp && S.arpPat[s] && S.arpPat[s] !== '.') { const a = S.arpPat[s], n = a === '1' ? ch[0] : a === '3' ? ch[1] : a === '5' ? ch[2] : ch[0] + 12; LEAD[S.arp](midiF(n + 12), t, sd, .45); }
            for (const n of S.bars[bar % bars]) if (n.s === s) LEAD[S.lead](songNote(S, n.deg), t, Math.max(n.len, Math.min(n.gap, 3)) * sd, .85);
          }
          const buf = await off.startRendering(); return wav(buf, loop, loop * 2);
        }, [k, rage]);
        saveOgg(path.join(sdir, k + (rage ? '_rage' : '') + '.ogg'), b64, rage ? 3 : 5);
      }
      console.log('song', k);
    }
    // 효과음
    const sfx = await page.evaluate(() => Object.keys(SONGS));
    const list = [['block', 'SFX.block(false)'], ['parry', 'SFX.block(true)'], ['hurt', 'SFX.hurt()'], ['miss', 'SFX.miss()'], ['coin', 'SFX.coin()'], ['win', 'SFX.win()', 1.6], ['lose', 'SFX.lose()', 1.8], ['lvl', 'SFX.lvl()', 1], ['chop', 'SFX.chop()'], ['mine', 'SFX.mine()'], ['pick', 'SFX.pick()'], ['door', 'SFX.door()'], ['start', 'SFX.start()'],
      ['trap', "tone(160, .3, 'sawtooth', .14, .5); noise(.25, .25, 900)"], ['whiff', 'noise(.08, .1, 2400)'], ['potion', "tone(600, .2, 'sine', .1, 1.8); tone(900, .25, 'sine', .06, 1.5, .1)"],
      ['sticks', 'MB = openBus(1); sticks(0.01, false)'], ['sticks_acc', 'MB = openBus(1); sticks(0.01, true)'], ['milestone', "[784, 988, 1175, 1568].forEach((f, i) => tone(f, .12, 'square', .04, 1, i * .05))", 1]];
    for (const m of ['fur', 'stone', 'goo', 'ice', 'sand', 'chitin', 'scale']) for (const p of [0, 1]) list.push([`hit_${m}_${p}`, `impactSnd('${m}', ${!!p})`]);
    for (const k of sfx) { list.push([`cry_${k}`, `VOICE.${k}.cry()`, 1.8], [`atk_${k}`, `VOICE.${k}.atk()`, 1]); list.push([`stab_${k}`, `MB = openBus(1); stab(SONGS.${k}, 0, 0.01, false)`, 1.2], [`stabh_${k}`, `MB = openBus(1); stab(SONGS.${k}, 0, 0.01, true)`, 1.6], [`chime_${k}`, `MB = openBus(1); chime(SONGS.${k}, 0, 0.01, true)`, .8]); }
    for (const [name, code, len] of list) {
      const b64 = await page.evaluate(async ([code, len]) => { const off = offline(len || .7); (0, eval)(code); const buf = await off.startRendering(); return wav(buf, 0, len || .7); }, [code, len]);
      saveOgg(path.join(fdir, name + '.ogg'), b64, 4);
    }
    console.log('sfx', list.length);
  }
  await browser.close();
})();
