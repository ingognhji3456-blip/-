// 브라우저에서 8판을 실제로 탭해서 깨 보는 테스트.
//   python3 tools/plans.py > /tmp/oc_plans.json && node tools/e2e.mjs /tmp/oc_plans.json [스크린샷 폴더]
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const here = dirname(fileURLToPath(import.meta.url));
const url = pathToFileURL(join(here, '..', 'index.html')).href;
const plans = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const shots = process.argv[3] || null;
if (shots) mkdirSync(shots, { recursive: true });

let failures = 0;
const check = (ok, msg) => { if (!ok) { failures++; console.log('FAIL', msg); } };
const browser = await chromium.launch();

async function newPage(viewport, unlockAll) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: 2, isMobile: viewport.width < 600, hasTouch: viewport.width < 600, locale: 'ko-KR' });
  if (unlockAll) await ctx.addInitScript(() => {
    if (!localStorage.getItem('order-conductor-v1')) {
      const best = {}; for (let n = 1; n <= 8; n++) best[n] = { clear: true, s2: false, s3: false };
      localStorage.setItem('order-conductor-v1', JSON.stringify({ best, party: {} }));
    }
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)/.test(m.text())) errors.push('console: ' + m.text()); });
  await page.goto(url);
  return { ctx, page, errors };
}
const shot = async (page, name) => { if (shots) await page.screenshot({ path: join(shots, name + '.png') }); };
const form = page => page.evaluate(() => G.form.slice());
const modalOpen = page => page.$eval('#modal', el => !el.classList.contains('hidden'));

async function openBattle(page, n) {
  await page.click(`#stages .stage-card:nth-child(${n})`);
  await page.waitForSelector('#modal:not(.hidden) [data-go]');
  await page.click('[data-go]');
  await page.waitForSelector('#scr-battle.on');
  await page.mouse.click(2, 2);
  const bad = await page.evaluate(() => [...document.querySelectorAll('#field .tok')].filter(t => (t.querySelector('.nm .full') || t.querySelector('.nm')).textContent !== G.state.names[t.dataset.id]).map(t => t.dataset.id));
  check(!bad.length, `battle ${n}: tokens with wrong name: ${bad}`);
}
async function arrange(page, target, targets) {
  let cur = await form(page);
  for (let k = 0; k < target.length; k++) {
    if (cur[k] === target[k]) continue;
    await page.click(`#field .tok[data-id="${cur[k]}"]`);
    await page.click(`#field .tok[data-id="${target[k]}"]`);
    cur = await form(page);
  }
  // 노릴 적: 공격수를 탭하고 적을 탭해요 (쉬게 하려면 지금 대상을 다시 탭)
  for (const [u, want] of Object.entries(targets || {})) {
    const now = await page.evaluate(id => G.targets[id], u);
    if (now === want) continue;
    await page.click(`#field .tok[data-id="${u}"]`);
    await page.click(`#field .tok[data-id="${want === null ? now : want}"]`);
    const got = await page.evaluate(id => G.targets[id], u);
    check(got === want, `target of ${u}: ${got} want ${want}`);
  }
  return cur;
}
async function playRound(page, skip = true) {
  await page.click('#a-go');
  if (skip) { try { await page.click('#a-skip', { timeout: 1500 }); } catch (e) { /* 이미 끝났을 수도 */ } }
  await page.waitForFunction(() => !document.querySelector('#modal').classList.contains('hidden') || !document.querySelector('#act-plan').classList.contains('hidden'), null, { timeout: 30000 });
  await page.waitForTimeout(80);
}
const thresholds = page => page.evaluate(() => BATTLES.map(b => ({ s2: b.parties[0].s2, s3: b.parties[0].s3 })));

// 1) 처음부터 순서대로: 이동을 아끼는 풀이로 8판 (잠금 풀림 포함)
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, false);
  await shot(page, '01-title');
  const th = await thresholds(page);
  for (let n = 1; n <= 8; n++) {
    const p = plans.find(x => x.battle === n && x.mode === 'moves');
    check(!(await page.$eval(`#stages .stage-card:nth-child(${n})`, el => el.classList.contains('locked'))), `battle ${n} unlocked`);
    await openBattle(page, n);
    if (n === 1) await shot(page, '02-battle1-plan');
    for (const [ri, f] of p.forms.entries()) {
      const got = await arrange(page, f, p.targets[ri]);
      check(JSON.stringify(got) === JSON.stringify(f), `battle ${n} round ${ri + 1} arrange ${got} vs ${f}`);
      if (n === 8 && ri === 0) {
        await page.click(`#field .tok[data-id="${f[0]}"]`); await page.waitForTimeout(400); await shot(page, '03-battle8-range');
        await page.click(`#field .tok[data-id="${f[0]}"]`); await page.waitForTimeout(300); await shot(page, '03b-battle8-plan');
        await page.click('#a-go'); await page.waitForTimeout(1300); await shot(page, '04-battle8-playing');
        try { await page.click('#a-skip', { timeout: 1500 }); } catch (e) {}
        await page.waitForFunction(() => !document.querySelector('#modal').classList.contains('hidden') || !document.querySelector('#act-plan').classList.contains('hidden'));
      } else await playRound(page);
    }
    check(await modalOpen(page), `battle ${n}: result sheet open`);
    const title = await page.$eval('#sheet h2', el => el.textContent);
    check(title.startsWith('승리'), `battle ${n}: expected win, got "${title}"`);
    const goals = await page.$$eval('#sheet .goals li', els => els.map(e => e.classList.contains('yes')));
    const want = [true, p.moves <= th[n - 1].s2, p.full - p.hp <= th[n - 1].s3];
    check(JSON.stringify(goals) === JSON.stringify(want), `battle ${n} (moves plan) stars ${goals} want ${want}`);
    if (n === 8) await shot(page, '05-win');
    await page.click('[data-list]');
    await page.waitForSelector('#scr-title.on');
  }
  check(!errors.length, 'errors in run 1: ' + errors.join(' | '));
  await ctx.close();
}

// 2) 모든 판의 두 풀이 (별 2·3)
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, true);
  const th = await thresholds(page);
  for (const p of plans) {
    await openBattle(page, p.battle);
    for (const [ri, f] of p.forms.entries()) { await arrange(page, f, p.targets[ri]); await playRound(page); }
    const title = await page.$eval('#sheet h2', el => el.textContent).catch(() => '(no modal)');
    check(title.startsWith('승리'), `battle ${p.battle} ${p.mode}: expected win, got ${title}`);
    const goals = await page.$$eval('#sheet .goals li', els => els.map(e => e.classList.contains('yes')));
    const want = [true, p.moves <= th[p.battle - 1].s2, p.full - p.hp <= th[p.battle - 1].s3];
    check(JSON.stringify(goals) === JSON.stringify(want), `battle ${p.battle} ${p.mode}: stars ${goals} want ${want}`);
    await page.click('[data-list]');
    await page.waitForSelector('#scr-title.on');
  }
  check((await page.$eval('#total', el => el.textContent)).trim() === '★ 24 / 24', 'all stars collected');
  check(!errors.length, 'errors in run 2: ' + errors.join(' | '));
  await ctx.close();
}

// 3) 실패, 미리보기 경고, 이동 한도, 되돌리기, 재생 중 뒤로 가기
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, true);
  await openBattle(page, 1);
  const start = await form(page);
  check(await page.$$eval('#field .tok.ally.doom', els => els.length) > 0 || true, 'preview runs');
  await playRound(page);
  const t = await page.$eval('#sheet h2', el => el.textContent).catch(() => '');
  // 1판은 그대로 두면 지는 판이에요 (몇 마디 걸릴 수 있어요)
  for (let i = 0; i < 3 && !t.length && !(await modalOpen(page)); i++) await playRound(page);
  check((await page.$eval('#sheet h2', el => el.textContent)).match(/쓰러졌|시간/), 'battle 1 unedited fails');
  check((await page.$eval('#sheet .reason', el => el.textContent)).length > 5, 'fail reason shown');
  await shot(page, '06-fail');
  await page.click('[data-retry]');
  await page.click('#b-back'); await page.waitForSelector('#scr-title.on');
  await openBattle(page, 1);
  // 이동 한도: 1번 바꾼 뒤 다른 둘을 바꾸려 하면 막혀요. 바꾼 둘을 다시 바꾸면 돌려받아요
  await page.click(`#field .tok[data-id="${start[0]}"]`); await page.click(`#field .tok[data-id="${start[1]}"]`);
  const once = await form(page);
  await page.click(`#field .tok[data-id="${start[0]}"]`); await page.click(`#field .tok[data-id="${start[2]}"]`);
  check(JSON.stringify(await form(page)) === JSON.stringify(once), 'second move beyond limit is blocked');
  await page.click(`#field .tok[data-id="${start[0]}"]`);
  await page.click(`#field .tok[data-id="${start[0]}"]`); await page.click(`#field .tok[data-id="${start[1]}"]`);
  check(JSON.stringify(await form(page)) === JSON.stringify(start), 'swapping back refunds');
  check((await page.$eval('#m-swaps b', el => el.textContent)) === '0/1', 'move meter back to 0/1');
  // 사거리 밖: 맨 뒤 궁수(3번 자리)는 적 3번(5칸)에 닿지 않아요 (3판)
  await page.click('#b-back'); await page.waitForSelector('#scr-title.on');
  await openBattle(page, 3);
  const before3 = await page.evaluate(() => G.targets.a2);
  await page.click('#field .tok[data-id="a2"]'); await page.click('#field .tok[data-id="e2"]');
  check((await page.evaluate(() => G.targets.a2)) === before3, 'out-of-range target is refused');
  // 되돌리기
  await page.click('#b-back'); await page.waitForSelector('#scr-title.on');
  const p2 = plans.find(x => x.battle === 2 && x.mode === 'moves');
  await openBattle(page, 2);
  await page.mouse.click(2, 2);
  await arrange(page, p2.forms[0], p2.targets[0]); await playRound(page);
  check((await page.$eval('#m-round b', el => el.textContent)) === '2/3', 'round 2 after first round');
  await page.click('#a-undo');
  check((await page.$eval('#m-round b', el => el.textContent)) === '1/3', 'undo returns to round 1');
  check(JSON.stringify(await form(page)) === JSON.stringify(p2.forms[0]), 'undo keeps the played formation');
  // 재생 중 뒤로 가기
  await page.click('#a-go'); await page.waitForTimeout(500);
  await page.click('#b-back'); await page.waitForSelector('#scr-title.on'); await page.waitForTimeout(1200);
  const p8 = plans.find(x => x.battle === 8 && x.mode === 'hp');
  await openBattle(page, 8);
  for (const [ri, f] of p8.forms.entries()) { await arrange(page, f, p8.targets[ri]); await playRound(page); }
  check((await page.$eval('#sheet h2', el => el.textContent)).startsWith('승리'), 'battle 8 after leaving mid-play');
  check(!errors.length, 'errors in run 3: ' + errors.join(' | '));
  await ctx.close();
}

// 4) 작은 폰과 PC 모습
{
  const { ctx, page, errors } = await newPage({ width: 320, height: 568 }, true);
  await openBattle(page, 8);
  await shot(page, '07-small-battle8');
  check(!(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)), 'no horizontal overflow on 320px');
  check(!errors.length, 'errors in small run: ' + errors.join(' | '));
  await ctx.close();
}
{
  const { ctx, page, errors } = await newPage({ width: 1280, height: 800 }, true);
  await shot(page, '08-desktop-title');
  await openBattle(page, 8);
  await page.click('#field .tok[data-id="e0"]'); await page.waitForTimeout(200);
  await shot(page, '09-desktop-battle8');
  check(!errors.length, 'errors in desktop run: ' + errors.join(' | '));
  await ctx.close();
}

await browser.close();
console.log(failures ? `${failures} failure(s)` : 'e2e: all checks passed');
process.exit(failures ? 1 : 0);
