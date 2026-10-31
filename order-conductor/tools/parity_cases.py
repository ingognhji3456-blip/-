#!/usr/bin/env python3
"""JS 엔진(index.html)과 이 검사기가 똑같이 움직이는지 대조할 사례를 만들어요.

    python3 tools/parity_cases.py > /tmp/oc_cases.json
    node tools/parity_test.mjs /tmp/oc_cases.json
"""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from solver import (BATTLES, UNITS, make, base_order, run_round, edit_costs, analyse, maxhp)

def jid(u):
    name, idx = u
    return f'a{idx}' if idx < 10 else f'e{idx - 10}'

def playthrough(allies, enemies, R, S, D, rng, shuffle=False):
    st = make(allies, enemies)
    rounds = []
    for _ in range(R):
        base = base_order(st)
        if shuffle:
            order = list(base); rng.shuffle(order); order = tuple(order); cost = None
        else:
            costs = edit_costs(base, S, D)
            order = rng.choice(sorted(costs))
            cost = costs[order] if D == 0 else None   # 게임의 지휘 횟수는 바꾸기만 세요 (미루기는 아직 없어요)
        log = []
        nst, res = run_round(st, order, log)
        rounds.append(dict(base=[jid(u) for u in base], order=[jid(u) for u in order], cost=cost,
                           log=log, result=res, A=[jid(u) for u in nst[0]], E=[jid(u) for u in nst[1]],
                           hp={jid(u): h for u, h in nst[2]}))
        st = nst
        if res: break
    return dict(allies=allies, enemies=enemies, rounds=rounds)

def main():
    rng = random.Random(20261031)
    cases, expect = [], []
    for n, (title, parties, enemies, R, S, D, lesson) in enumerate(BATTLES, 1):
        for party in parties:
            for _ in range(60): cases.append(playthrough(party, enemies, R, S, D, rng))
            for _ in range(30): cases.append(playthrough(party, enemies, R, S, D, rng, shuffle=True))
            st = make(party, enemies)
            a = analyse(st, R, S, D)
            capped = analyse(st, R, S, D, cap=a['min_edits'])
            expect.append(dict(battle=n, title=title, allies=party, enemies=enemies, rounds=R, swaps=S,
                               s2=a['min_edits'], s3=a['full_hp'] - a['best_hp'],
                               clash=capped['best_hp'] < a['best_hp']))
    # 지금 판에는 안 나오지만 엔진이 지원하는 규칙(연쇄 폭발, 방패 둘, 도둑쥐)도 대조해요.
    extra = [
        (['방패병', '방패병', '기사'], ['고블린', '폭탄벌레', '폭탄벌레', '해골궁수']),
        (['사제', '방패병', '궁수'], ['폭탄벌레', '폭탄벌레', '도둑쥐', '주술사']),
        (['기사', '사제', '궁수'], ['도둑쥐', '트롤', '폭탄벌레', '도둑쥐']),
        (['궁수', '궁수', '방패병'], ['폭탄벌레', '폭탄벌레', '폭탄벌레']),
    ]
    for allies, enemies in extra:
        for _ in range(80): cases.append(playthrough(allies, enemies, 4, 2, 1, rng))
        for _ in range(40): cases.append(playthrough(allies, enemies, 4, 2, 1, rng, shuffle=True))
    json.dump(dict(cases=cases, expect=expect), sys.stdout, ensure_ascii=False)

if __name__ == '__main__':
    main()
