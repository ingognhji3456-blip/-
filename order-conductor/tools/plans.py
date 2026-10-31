#!/usr/bin/env python3
"""브라우저 테스트(tools/e2e.mjs)가 그대로 따라 할 풀이를 판·파티마다 두 개씩 뽑아요.
- edits: 지휘를 가장 적게 쓰는 풀이 (그중 체력을 가장 많이 남기는 것) → ★2 확실
- hp:    체력을 가장 많이 남기는 풀이 (그중 지휘를 가장 적게 쓰는 것) → ★3 확실
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from solver import BATTLES, make, base_order, run_round, edit_costs, analyse, ally_hp

def jid(u):
    return f'a{u[1]}' if u[1] < 10 else f'e{u[1] - 10}'

def plan(st, R, S, D, mode):
    full = analyse(st, R, S, D)
    if mode == 'edits':
        cap = full['min_edits']; want = analyse(st, R, S, D, cap=cap)['best_hp']
    else:
        want = full['best_hp']
        cap = next(c for c in range(0, R * S + 1) if (analyse(st, R, S, D, cap=c)['best_hp'] or -1) >= want)
    out, left = [], cap
    for r in range(R):
        costs = edit_costs(base_order(st), S, D)
        for o, c in sorted(costs.items(), key=lambda x: (x[1], x[0])):
            if c > left: continue
            nst, res = run_round(st, o)
            if (res == 'win' and ally_hp(nst) >= want) or (
                    res is None and (analyse(nst, R - r - 1, S, D, cap=left - c)['best_hp'] or -1) >= want):
                out.append([jid(u) for u in o]); st, left = nst, left - c
                break
        else:
            raise SystemExit('no plan')
        if res == 'win': break
    return dict(orders=out, edits=cap - left, hp=want)

res = []
for n, (title, parties, enemies, R, S, D, lesson) in enumerate(BATTLES, 1):
    for party in parties:
        st = make(party, enemies)
        for mode in ('edits', 'hp'):
            p = plan(st, R, S, D, mode)
            res.append(dict(battle=n, party=party[0], mode=mode, full=sum(__import__('solver').maxhp(u) for u in st[0]), **p))
json.dump(res, sys.stdout, ensure_ascii=False)
