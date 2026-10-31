#!/usr/bin/env python3
"""브라우저 테스트(tools/e2e.mjs)가 그대로 따라 할 풀이를 판마다 두 개씩 뽑아요.
- moves: 이동을 가장 적게 쓰는 풀이 (그중 체력을 가장 많이 남기는 것) → ★2 확실
- hp:    체력을 가장 많이 남기는 풀이 (그중 이동을 가장 적게 쓰는 것) → ★3 확실
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from solver import BATTLES, make, find_plan, run_round, ally_hp, maxhp

def jid(u):
    return f'a{u[1]}' if u[1] < 10 else f'e{u[1] - 10}'

res = []
for n, (title, allies, enemies, R, S, lesson) in enumerate(BATTLES, 1):
    st0 = make(allies, enemies)
    for mode in ('moves', 'hp'):
        plan = find_plan(st0, R, S, mode)
        st = st0
        for A, c, log in plan: st, _ = run_round(st, A)
        res.append(dict(battle=n, mode=mode, forms=[[jid(u) for u in A] for A, c, log in plan],
                        moves=sum(c for A, c, log in plan), hp=ally_hp(st), full=sum(maxhp(u) for u in st0[0])))
json.dump(res, sys.stdout, ensure_ascii=False)
