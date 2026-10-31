// index.html 의 규칙 엔진이 tools/solver.py 와 한 줄도 안 틀리게 똑같은지 대조해요.
//   python3 tools/parity_cases.py > /tmp/oc_cases.json && node tools/parity_test.mjs /tmp/oc_cases.json
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, '..', 'index.html'), 'utf8');
const block = (a, b) => { const i = html.indexOf(a), j = html.indexOf(b); if (i < 0 || j < 0) throw new Error('marker missing: ' + a); return html.slice(i, j); };
const src = block('/* ENGINE:BEGIN', '/* ENGINE:END */') + '\n' + block('/* DATA:BEGIN', '/* DATA:END */');
const E = new Function(src + '\nreturn { UNITS, makeState, runRound, swapDistance, BATTLES };')();

const { cases, expect } = JSON.parse(readFileSync(process.argv[2], 'utf8'));
let rounds = 0, fails = 0;
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sortObj = o => Object.fromEntries(Object.keys(o).sort().map(k => [k, o[k]]));
for (const [ci, c] of cases.entries()) {
  let s = E.makeState(c.allies, c.enemies);
  for (const [ri, r] of c.rounds.entries()) {
    rounds++;
    const where = `case ${ci} (${c.allies.join('·')} vs ${c.enemies.join('·')}) round ${ri + 1}`;
    if (r.cost !== null && E.swapDistance(s.A, r.A) !== r.cost) { fails++; console.log('COST', where, E.swapDistance(s.A, r.A), r.cost); }
    const out = E.runRound(s, r.A, r.T);
    if (!eq(out.log, r.log)) { fails++; console.log('LOG', where, '\n  js:', out.log, '\n  py:', r.log); break; }
    if (out.result !== r.result) { fails++; console.log('RESULT', where, out.result, r.result); break; }
    if (!eq(out.state.A, r.A2) || !eq(out.state.E, r.E2) || !eq(sortObj(out.state.hp), sortObj(r.hp)) || !eq(sortObj(out.state.fuse), sortObj(r.fuse))) {
      fails++; console.log('STATE', where, JSON.stringify(out.state), JSON.stringify(r)); break;
    }
    s = out.state;
  }
}
let dataFails = 0;
for (const x of expect) {
  const b = E.BATTLES[x.battle - 1], p = b && b.parties[0];
  const want = { title: x.title, enemies: x.enemies, rounds: x.rounds, swaps: x.swaps, allies: x.allies, s2: x.s2, s3: x.s3, clash: x.clash };
  const got = b ? { title: b.title, enemies: b.enemies, rounds: b.rounds, swaps: b.swaps, allies: p.allies, s2: p.s2, s3: p.s3, clash: p.clash } : null;
  if (!eq(want, got)) { dataFails++; console.log('DATA', x.battle, '\n  js:', got, '\n  py:', want); }
}
if (E.BATTLES.length !== expect.length) { dataFails++; console.log('DATA battle count', E.BATTLES.length, expect.length); }
console.log(`engine: ${cases.length} playthroughs, ${rounds} rounds, ${fails} mismatches`);
console.log(`data:   ${expect.length} battles, ${dataFails} mismatches`);
process.exit(fails || dataFails ? 1 : 0);
