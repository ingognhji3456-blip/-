#!/usr/bin/env python3
"""JS 엔진(index.html)과 이 검사기가 똑같이 움직이는지 대조할 사례를 만들어요.

    python3 tools/parity_cases.py > /tmp/oc_cases.json
    node tools/parity_test.mjs /tmp/oc_cases.json
"""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from solver import BATTLES, make, run_round, moves, analyse, target_choices, targets_for

def jid(u):
    name, idx = u
    return f'a{idx}' if idx < 10 else f'e{idx - 10}'

def playthrough(allies, enemies, R, S, rng, anywhere=False):
    st = make(allies, enemies)
    rounds = []
    for _ in range(R):
        if anywhere:
            A = list(st[0]); rng.shuffle(A); A = tuple(A); cost = None
            # 아무 적이나 (사거리 밖도) 골라서 엔진이 막는지도 봐요
            T = {u: rng.choice(list(st[1]) + [None]) for u in A if u[0] in ('기사', '궁수')}
        else:
            opts = moves(st[0], S); A = rng.choice(sorted(opts)); cost = opts[A]
            T = rng.choice(target_choices(st, A))
        log = []
        nst, res = run_round(st, A, T, log)
        rounds.append(dict(A=[jid(u) for u in A], T={jid(u): (jid(t) if t else None) for u, t in T.items()}, cost=cost, log=log, result=res,
                           A2=[jid(u) for u in nst[0]], E2=[jid(u) for u in nst[1]],
                           hp={jid(u): h for u, h in nst[2]}, fuse={jid(u): f for u, f in nst[3]}))
        st = nst
        if res: break
    return dict(allies=allies, enemies=enemies, rounds=rounds)

def main():
    rng = random.Random(20261031)
    cases, expect = [], []
    for n, (title, allies, enemies, R, S, lesson) in enumerate(BATTLES, 1):
        for _ in range(80): cases.append(playthrough(allies, enemies, R, S, rng))
        for _ in range(40): cases.append(playthrough(allies, enemies, R + 1, S, rng, anywhere=True))
        st = make(allies, enemies)
        a = analyse(st, R, S); cap = analyse(st, R, S, cap=a['min_moves'])
        expect.append(dict(battle=n, title=title, allies=allies, enemies=enemies, rounds=R, swaps=S,
                           s2=a['min_moves'], s3=a['full_hp'] - a['best_hp'], clash=cap['best_hp'] < a['best_hp']))
    # 판에는 안 나오지만 엔진이 지원하는 조합(폭탄 연쇄, 방패병과 휩쓸기, 주술사 여럿)도 대조해요
    extra = [
        (['방패병', '사제', '기사', '궁수'], ['폭탄벌레', '폭탄벌레', '고블린', '폭탄벌레']),
        (['기사', '방패병', '사제', '궁수'], ['트롤', '주술사', '해골궁수', '주술사']),
        (['사제', '궁수', '기사'], ['폭탄벌레', '해골궁수', '폭탄벌레']),
        (['궁수', '사제', '방패병', '기사'], ['고블린', '고블린', '고블린', '트롤']),
    ]
    for allies, enemies in extra:
        for _ in range(80): cases.append(playthrough(allies, enemies, 5, 2, rng))
        for _ in range(60): cases.append(playthrough(allies, enemies, 5, 2, rng, anywhere=True))
    json.dump(dict(cases=cases, expect=expect), sys.stdout, ensure_ascii=False)

if __name__ == '__main__':
    main()
