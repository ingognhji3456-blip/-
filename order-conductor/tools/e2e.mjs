// 브라우저에서 8판을 실제로 클릭해서 깨 보는 테스트.
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
const tiles = page => page.$$eval('#tiles .tile', els => els.map(e => e.dataset.id));
const modalOpen = page => page.$eval('#modal', el => !el.classList.contains('hidden'));

async function openBattle(page, n, partyKey) {
  await page.click(`#stages .stage-card:nth-child(${n})`);
  await page.waitForSelector('#modal:not(.hidden) [data-go]');
  const opt = await page.$(`[data-party="${partyKey}"]`);
  if (opt) await opt.click();
  await page.click('[data-go]');
  await page.waitForSelector('#scr-battle.on');
  const bad = await page.evaluate(() => [...document.querySelectorAll('#tiles .tile')].filter(t => (t.querySelector('.tn .full') || t.querySelector('.tn')).textContent !== G.state.names[t.dataset.id]).map(t => t.dataset.id));
  check(!bad.length, `battle ${n}: tiles with wrong unit name: ${bad}`);
}
async function arrange(page, target) {
  let cur = await tiles(page);
  for (let k = 0; k < target.length; k++) {
    if (cur[k] === target[k]) continue;
    await page.click(`#tiles .tile[data-id="${cur[k]}"]`);
    await page.click(`#tiles .tile[data-id="${target[k]}"]`);
    cur = await tiles(page);
  }
  return cur;
}
async function playRound(page, skip = true) {
  await page.click('#a-go');
  if (skip) { try { await page.click('#a-skip', { timeout: 1500 }); } catch (e) { /* 이미 끝났을 수도 */ } }
  await page.waitForFunction(() => !document.querySelector('#modal').classList.contains('hidden') || !document.querySelector('#act-plan').classList.contains('hidden'), null, { timeout: 30000 });
  await page.waitForTimeout(80);
}

// 1) 처음부터 순서대로: 지휘를 아끼는 풀이로 8판 (잠금 풀림 확인 포함)
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, false);
  await shot(page, '01-title');
  const data = await page.evaluate(() => BATTLES.map(b => ({ title: b.title, parties: b.parties.map(p => ({ key: p.key, s2: p.s2, s3: p.s3 })) })));
  for (let n = 1; n <= 8; n++) {
    const p = plans.find(x => x.battle === n && x.mode === 'edits' && x.party === data[n - 1].parties[0].key);
    const locked = await page.$eval(`#stages .stage-card:nth-child(${n})`, el => el.classList.contains('locked'));
    check(!locked, `battle ${n} should be unlocked after clearing ${n - 1}`);
    if (n === 6) { await page.click(`#stages .stage-card:nth-child(6)`); await page.waitForSelector('[data-go]'); await shot(page, '06-intro-party'); await page.click('[data-close]'); }
    await openBattle(page, n, p.party);
    if (n === 1) await shot(page, '02-battle1-plan');
    for (const [ri, order] of p.orders.entries()) {
      const got = await arrange(page, order);
      check(JSON.stringify(got) === JSON.stringify(order), `battle ${n} round ${ri + 1} arrange`);
      if (n === 7 && ri === 0) {
        await page.click(`#field .tok[data-id="${order[0]}"]`); await page.waitForTimeout(150);
        await shot(page, '03-battle7-arranged');
        await page.click(`#field .tok[data-id="${order[0]}"]`);
        await page.click('#a-go'); await page.waitForTimeout(700); await shot(page, '04-battle7-playing');
        try { await page.click('#a-skip', { timeout: 1500 }); } catch (e) {}
        await page.waitForFunction(() => !document.querySelector('#modal').classList.contains('hidden') || !document.querySelector('#act-plan').classList.contains('hidden'));
      } else {
        await playRound(page);
      }
    }
    check(await modalOpen(page), `battle ${n}: modal should be open after last round`);
    const title = await page.$eval('#sheet h2', el => el.textContent);
    check(title.startsWith('승리'), `battle ${n}: expected win, got "${title}"`);
    const goals = await page.$$eval('#sheet .goals li', els => els.map(e => e.classList.contains('yes')));
    const party = data[n - 1].parties.find(q => q.key === p.party);
    const lost = p.full - p.hp;
    const want = [true, p.edits <= party.s2, lost <= party.s3];
    check(JSON.stringify(goals) === JSON.stringify(want), `battle ${n} (${p.party}, edits plan) stars ${goals} want ${want}`);
    if (n === 8) await shot(page, '05-win');
    await page.click('[data-list]');
    await page.waitForSelector('#scr-title.on');
  }
  await shot(page, '07-title-after');
  check(!errors.length, 'errors in run 1: ' + errors.join(' | '));
  await ctx.close();
}

// 2) 모든 판·파티의 두 풀이를 다 해 보기 (별 2·3 확인)
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, true);
  const data = await page.evaluate(() => BATTLES.map(b => ({ parties: b.parties.map(p => ({ key: p.key, s2: p.s2, s3: p.s3 })) })));
  for (const p of plans) {
    await openBattle(page, p.battle, p.party);
    for (const order of p.orders) { await arrange(page, order); await playRound(page); }
    const title = await page.$eval('#sheet h2', el => el.textContent).catch(() => '(no modal)');
    check(title.startsWith('승리'), `battle ${p.battle} ${p.party} ${p.mode}: expected win, got ${title}`);
    const goals = await page.$$eval('#sheet .goals li', els => els.map(e => e.classList.contains('yes')));
    const party = data[p.battle - 1].parties.find(q => q.key === p.party);
    const want = [true, p.edits <= party.s2, p.full - p.hp <= party.s3];
    check(JSON.stringify(goals) === JSON.stringify(want), `battle ${p.battle} ${p.party} ${p.mode}: stars ${goals} want ${want}`);
    await page.click('[data-list]');
    await page.waitForSelector('#scr-title.on');
  }
  const total = await page.$eval('#total', el => el.textContent);
  check(total.trim() === '★ 24 / 24', 'all stars collected: ' + total);
  check(!errors.length, 'errors in run 2: ' + errors.join(' | '));
  await ctx.close();
}

// 3) 실패, 되돌리기, 바꾸기 한도
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, true);
  await openBattle(page, 1, '사제');
  const base = await tiles(page);
  await playRound(page);
  check((await page.$eval('#sheet h2', el => el.textContent)).includes('쓰러졌'), 'battle 1 unedited should fail');
  const reason = await page.$eval('#sheet .reason', el => el.textContent);
  check(reason.includes('궁수가 쓰러졌어요'), 'fail reason mentions 궁수: ' + reason);
  await shot(page, '08-fail');
  await page.click('[data-retry]');
  check(JSON.stringify(await tiles(page)) === JSON.stringify(base), 'retry restores the same order');
  // 바꾸기 한도: 1번 바꾼 뒤 다른 둘을 바꾸려 하면 막혀요. 바꾼 둘을 다시 바꾸면 돌려받아요.
  await page.click(`#tiles .tile[data-id="${base[0]}"]`); await page.click(`#tiles .tile[data-id="${base[1]}"]`);
  const once = await tiles(page);
  await page.click(`#tiles .tile[data-id="${base[2]}"]`); await page.click(`#tiles .tile[data-id="${base[3]}"]`);
  check(JSON.stringify(await tiles(page)) === JSON.stringify(once), 'second swap beyond limit is blocked');
  await page.click(`#tiles .tile[data-id="${base[2]}"]`);   // 골라진 것 취소
  await page.click(`#tiles .tile[data-id="${base[0]}"]`); await page.click(`#tiles .tile[data-id="${base[1]}"]`);
  check(JSON.stringify(await tiles(page)) === JSON.stringify(base), 'swapping back refunds');
  check((await page.$eval('#m-swaps b', el => el.textContent)) === '0/1', 'swap meter back to 0/1');
  // 되돌리기: 2판에서 1마디 진행 뒤 지난 마디로
  await page.click('#b-back'); await page.waitForSelector('#scr-title.on');
  const p2 = plans.find(x => x.battle === 2 && x.mode === 'edits');
  await openBattle(page, 2, '사제');
  await page.mouse.click(5, 5);           // 안내 말풍선 닫기용 빈 곳
  await arrange(page, p2.orders[0]); await playRound(page);
  check((await page.$eval('#m-round b', el => el.textContent)) === '2/3', 'round 2 after first round');
  check(!(await page.$eval('#a-undo', el => el.disabled)), 'undo enabled in round 2');
  await page.click('#a-undo');
  check((await page.$eval('#m-round b', el => el.textContent)) === '1/3', 'undo returns to round 1');
  check(JSON.stringify(await tiles(page)) === JSON.stringify(p2.orders[0]), 'undo keeps the order that was played');
  check(!errors.length, 'errors in run 3: ' + errors.join(' | '));
  await ctx.close();
}

// 3b) 재생 중에 뒤로 가기 → 오류 없이 목록, 다시 들어가도 정상
{
  const { ctx, page, errors } = await newPage({ width: 390, height: 844 }, true);
  await openBattle(page, 8, '사제');
  await page.click('#a-go'); await page.waitForTimeout(600);
  await page.click('#b-back'); await page.waitForSelector('#scr-title.on'); await page.waitForTimeout(1500);
  const p8 = plans.find(x => x.battle === 8 && x.party === '사제' && x.mode === 'hp');
  await openBattle(page, 8, '사제');
  for (const order of p8.orders) { await arrange(page, order); await playRound(page); }
  check((await page.$eval('#sheet h2', el => el.textContent)).startsWith('승리'), 'battle 8 after back-during-play still winnable');
  check(!errors.length, 'errors in run 3b: ' + errors.join(' | '));
  await ctx.close();
}

// 작은 폰(320x568) 모습
{
  const { ctx, page, errors } = await newPage({ width: 320, height: 568 }, true);
  await openBattle(page, 8, '사제');
  await page.click('#field .tok[data-id="e1"]'); await page.waitForTimeout(150);
  await shot(page, '11-small-battle8');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  check(!overflow, 'no horizontal overflow on 320px');
  check(!errors.length, 'errors in small run: ' + errors.join(' | '));
  await ctx.close();
}

// 4) PC 화면 모습
{
  const { ctx, page, errors } = await newPage({ width: 1280, height: 800 }, true);
  await shot(page, '09-desktop-title');
  await openBattle(page, 8, '사제');
  await page.click('#field .tok[data-id="e1"]'); await page.waitForTimeout(150);
  await shot(page, '10-desktop-battle8');
  check(!errors.length, 'errors in run 4: ' + errors.join(' | '));
  await ctx.close();
}

await browser.close();
console.log(failures ? `${failures} failure(s)` : 'e2e: all checks passed');
process.exit(failures ? 1 : 0);
