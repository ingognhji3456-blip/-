#!/usr/bin/env python3
"""순서 지휘자 — 규칙 시뮬레이터 + 판 검사기.

설계 문서(../DESIGN.md)의 규칙을 그대로 옮긴 것이에요. 판을 새로 만들거나 수치를 바꾸면
이 파일로 '풀리는지, 너무 쉽지 않은지, 별 조건이 몇인지'를 먼저 확인해요.

    python3 solver.py                         # 8개 판 전부 (파티를 고르는 판은 파티별로)
    python3 solver.py 6 8                     # 6번, 8번 판만
    python3 solver.py --trace 7               # 7번 판의 풀이를 한 마디씩
    python3 solver.py --party 방패병,궁수,기사 5   # 파티를 바꿔서 검사 (뒤→앞)

용어
- 줄(line): 아군은 뒤→앞, 적은 앞→뒤. 맨 앞끼리 맞닿아 있어요.
- 마디(round): 모두가 순서표대로 한 번씩 행동하는 단위.
- 지휘: 마디 시작 전에 순서표를 고치는 것. 횟수는 마디마다 다시 채워져요.
"""
import itertools
import sys

# 이름: (편, 체력, 수치, 습관, 빠르기)
UNITS = {
    '기사':     ('A', 9, 3, 'front', 3),    # 맨 앞 적에게 3
    '궁수':     ('A', 5, 2, 'back', 5),     # 맨 뒤 적에게 2
    '사제':     ('A', 5, 2, 'heal', 2),     # 잃은 체력이 가장 큰 아군(자신 포함) 2 회복
    '방패병':   ('A', 10, 0, 'shield', 1),  # 행동한 뒤 그 마디 끝까지 적의 한 명 노리기 공격을 대신 맞음
    '고블린':   ('E', 6, 3, 'front', 3),    # 맨 앞 아군에게 3
    '해골궁수': ('E', 3, 3, 'weakest', 4),  # 지금 체력 숫자가 가장 낮은 아군에게 3
    '폭탄벌레': ('E', 3, 4, 'bomb', 1),     # 차례가 오거나 쓰러지면 터져 양옆에 4 (편 안 가림)
    '주술사':   ('E', 4, 3, 'heal', 2),     # 잃은 체력이 가장 큰 적(자신 포함) 3 회복
    '트롤':     ('E', 14, 5, 'front', 1),   # 맨 앞 아군에게 5
    '도둑쥐':   ('E', 2, 0, 'thief', 6),    # (나중에) 순서표에서 다음 살아 있는 유닛을 맨 뒤로
}

TRIO = ['사제', '궁수', '기사']          # 기본 파티 (뒤→앞)
SHIELD = ['방패병', '궁수', '기사']
CHOICE = [TRIO, SHIELD]                  # 6판부터: 맨 뒤 자리에 사제 또는 방패병

# 판: (제목, 파티 후보들, 적 앞→뒤, 마디 수, 마디당 바꾸기, 마디당 미루기, 배우는 것)
BATTLES = [
    ('첫 마디',     [TRIO],   ['해골궁수', '해골궁수'],                3, 1, 0, '기사를 적 궁수보다 먼저'),
    ('약한 놈부터', [TRIO],   ['해골궁수', '고블린', '해골궁수'],       3, 1, 0, '복습: 위험한 적을 내 기사 뒤로'),
    ('폭탄벌레',    [TRIO],   ['폭탄벌레', '해골궁수', '해골궁수'],     3, 1, 0, '폭탄은 양옆을 다 때려요 (쓰러져도 터져요)'),
    ('주술사',      [TRIO],   ['해골궁수', '고블린', '주술사'],         3, 2, 0, '주술사를 먼저 움직여 헛손질시키기'),
    ('방패병',      [SHIELD], ['해골궁수', '해골궁수', '해골궁수'],     3, 1, 0, '느린 방패병을 적보다 먼저'),
    ('트롤',        CHOICE,   ['트롤', '폭탄벌레', '고블린'],           4, 2, 0, '폭탄이 고블린보다 먼저 터지게'),
    ('지휘봉 하나', CHOICE,   ['폭탄벌레', '고블린', '고블린'],         3, 1, 0, '폭탄을 맨 앞으로, 적끼리 맞게'),
    ('마지막 곡',   CHOICE,   ['트롤', '폭탄벌레', '해골궁수', '주술사'], 4, 2, 0, '주술사 헛손질 + 큰 적'),
]


def side(u): return UNITS[u[0]][0]
def maxhp(u): return UNITS[u[0]][1]
def power(u): return UNITS[u[0]][2]
def habit(u): return UNITS[u[0]][3]
def speed(u): return UNITS[u[0]][4]


def make(allies, enemies):
    """상태 = (아군 뒤→앞, 적 앞→뒤, 체력표). 유닛 id = (이름, 번호)."""
    A = tuple((n, i) for i, n in enumerate(allies))
    E = tuple((n, 10 + i) for i, n in enumerate(enemies))
    return (A, E, tuple(sorted((u, maxhp(u)) for u in A + E)))


def base_order(state):
    """마디마다 새로 짜는 기본 순서표: 빠른 순 → 지금 줄에서 더 앞 → 아군 먼저."""
    A, E, _ = state
    af, ef = list(reversed(A)), list(E)
    key = {u: (-speed(u), i, 0) for i, u in enumerate(af)}
    key.update({u: (-speed(u), i, 1) for i, u in enumerate(ef)})
    return tuple(sorted(af + ef, key=key.get))


def run_round(state, order, log=None):
    """한 마디 실행. 반환: (새 상태, 'win' | 'lose' | None).

    승패는 한 유닛의 행동(연쇄 폭발 포함)이 모두 끝난 뒤에 판정하고, 실패를 먼저 봐요.
    """
    A, E, hp = state
    A, E, hp, bar = list(A), list(E), dict(hp), list(order)
    n_allies = len(A)
    shields = []                       # 방패를 든 순서대로

    def alive(u): return hp.get(u, 0) > 0
    def line(): return A + E
    def foes(u): return E if side(u) == 'A' else A[::-1]     # 맨 앞부터
    def mates(u): return A[::-1] if side(u) == 'A' else E    # 맨 앞부터
    def say(s):
        if log is not None: log.append(s)

    def remove(u):
        if u in A: A.remove(u)
        if u in E: E.remove(u)

    def boom(u):
        # 폭탄은 먼저 줄에서 빠지고, 그 순간의 양옆이 왼쪽→오른쪽 순으로 맞아요.
        # 맞아서 쓰러진 폭탄은 그 자리(이미 줄어든 줄)에서 곧바로 터져요.
        L = line(); p = L.index(u)
        near = [L[j] for j in (p - 1, p + 1) if 0 <= j < len(L)]
        hp[u] = 0; remove(u)
        say(f'{u[0]} 펑! → {", ".join(t[0] for t in near) or "없음"}')
        for t in near:
            if alive(t): hit(t, power(u))

    def hit(t, dmg):
        hp[t] -= dmg
        if hp[t] <= 0:
            if habit(t) == 'bomb':
                hp[t] = 1; boom(t)
            else:
                hp[t] = 0; remove(t); say(f'  {t[0]} 쓰러짐')

    result = None
    i = 0
    while i < len(bar):
        u = bar[i]; i += 1
        if not alive(u):
            continue                   # 쓰러진 유닛은 건너뛰어요
        h, f = habit(u), foes(u)
        if h in ('front', 'back', 'weakest'):
            if not f:
                continue
            guard = [s for s in shields if alive(s) and side(s) != side(u)]
            if guard:
                t = guard[0]
            elif h == 'front':
                t = f[0]
            elif h == 'back':
                t = f[-1]
            else:
                t = min(f, key=lambda x: (hp[x], f.index(x)))
            say(f'{u[0]} → {t[0]} {power(u)}')
            hit(t, power(u))
        elif h == 'heal':
            m = mates(u)
            hurt = [x for x in m if hp[x] < maxhp(x)]
            if hurt:
                t = max(hurt, key=lambda x: (maxhp(x) - hp[x], -m.index(x)))
                gain = min(maxhp(t), hp[t] + power(u)) - hp[t]
                hp[t] += gain
                say(f'{u[0]} → {t[0]} +{gain}')
            else:
                say(f'{u[0]} 쉼 (다친 편이 없어요)')
        elif h == 'bomb':
            boom(u)
        elif h == 'shield':
            if u not in shields: shields.append(u)
            say(f'{u[0]} 방패!')
        elif h == 'thief':
            for j in range(i, len(bar)):
                if alive(bar[j]):
                    v = bar.pop(j); bar.append(v); say(f'{u[0]}: {v[0]} 맨 뒤로'); break
        if len(A) < n_allies: result = 'lose'; break
        if not E: result = 'win'; break
    hpt = tuple(sorted((x, v) for x, v in hp.items() if v > 0))
    return (tuple(A), tuple(E), hpt), result


_edit_cache = {}
def edit_costs(order, swaps, delays):
    """기본 순서표에서 만들 수 있는 서로 다른 순서표 → 최소 지휘 횟수 (안 고친 것 = 0)."""
    key = (order, swaps, delays)
    if key in _edit_cache: return _edit_cache[key]
    best = {order: 0}
    seen = {(order, swaps, delays)}
    frontier = [(order, swaps, delays, 0)]
    while frontier:
        nxt = []
        for o, s, d, c in frontier:
            moves = []
            if s:
                for a, b in itertools.combinations(range(len(o)), 2):
                    l = list(o); l[a], l[b] = l[b], l[a]; moves.append((tuple(l), s - 1, d))
            if d:
                for a in range(len(o) - 1):       # 이미 맨 뒤인 유닛은 미룰 수 없어요
                    l = list(o); l.append(l.pop(a)); moves.append((tuple(l), s, d - 1))
            for m in moves:
                if m not in seen:
                    seen.add(m); nxt.append((*m, c + 1))
                    if m[0] not in best: best[m[0]] = c + 1
        frontier = nxt
    _edit_cache[key] = best
    return best


def ally_hp(state):
    A, _, hp = state
    d = dict(hp)
    return sum(d[u] for u in A)


def analyse(state, rounds, swaps, delays, cap=None):
    """풀 수 있는지, 최소 마디, 최소 지휘(판 전체 합), 최대로 남길 수 있는 체력,
    무작위로 고를 때 이길 확률. cap을 주면 판 전체 지휘 합이 cap 이하인 풀이만 봐요."""
    memo = {}
    def go(st, r, left):
        k = (st, r, left)
        if k in memo: return memo[k]
        if r == 0:
            memo[k] = (None, None, 0.0, None); return memo[k]
        costs = edit_costs(base_order(st), swaps, delays)
        opts = [(o, c) for o, c in costs.items() if left is None or c <= left]
        best_r = best_e = best_h = None; p = 0.0
        for o, c in opts:
            nst, res = run_round(st, o)
            if res == 'win':
                mr, me, q, mh = 1, c, 1.0, ally_hp(nst)
            elif res == 'lose':
                mr, me, q, mh = None, None, 0.0, None
            else:
                sr, se, q, sh = go(nst, r - 1, None if left is None else left - c)
                mr, me, mh = (None, None, None) if sr is None else (sr + 1, se + c, sh)
            if mr is not None:
                best_r = mr if best_r is None else min(best_r, mr)
                best_e = me if best_e is None else min(best_e, me)
                best_h = mh if best_h is None else max(best_h, mh)
            p += q
        memo[k] = (best_r, best_e, p / len(opts), best_h)
        return memo[k]
    r, e, p, h = go(state, rounds, cap)
    return dict(solvable=r is not None, min_rounds=r, min_edits=e, random_win=p,
                best_hp=h, full_hp=sum(maxhp(u) for u in state[0]))


def first_move_rate(state, rounds, swaps, delays):
    """첫 마디에 '딱 한 번만 고치는 수' 가운데 이길 길이 남는 수의 비율."""
    costs = edit_costs(base_order(state), swaps, delays)
    ones = [o for o, c in costs.items() if c == 1]
    good = 0
    for o in ones:
        nst, res = run_round(state, o)
        if res == 'win' or (res is None and analyse(nst, rounds - 1, swaps, delays)['solvable']):
            good += 1
    return good, len(ones)


def default_play(state, rounds):
    st = state
    for r in range(rounds):
        st, res = run_round(st, base_order(st))
        if res: return res, r + 1
    return 'timeout', rounds


def find_plan(state, rounds, swaps, delays):
    """지휘를 가장 적게 쓰는 풀이 하나 (그중 체력을 가장 많이 남기는 것)."""
    target = analyse(state, rounds, swaps, delays)
    cap = target['min_edits']
    want = analyse(state, rounds, swaps, delays, cap=cap)['best_hp']
    out = []
    left = cap
    for r in range(rounds):
        costs = edit_costs(base_order(state), swaps, delays)
        for o, c in sorted(costs.items(), key=lambda x: (x[1], x[0])):
            if c > left: continue
            nst, res = run_round(state, o)
            ok = (res == 'win' and ally_hp(nst) >= want) or (
                res is None and (analyse(nst, rounds - r - 1, swaps, delays, cap=left - c)['best_hp'] or -1) >= want)
            if ok:
                log = []; run_round(state, o, log)
                out.append((r + 1, [u[0] for u in base_order(state)], [u[0] for u in o], c, log))
                state, left = nst, left - c
                break
        if res == 'win': break
    return out


def check(n, title, party, enemies, R, S, D, lesson, trace=False):
    st = make(party, enemies)
    a = analyse(st, R, S, D)
    d = default_play(st, R)
    ok = a['solvable'] and d[0] != 'win'
    print(f'{"OK " if ok else "!! "}{n}. {title}  파티={"·".join(party)}  적={"·".join(enemies)}  마디 {R} · 바꾸기 {S}/마디' + (f' · 미루기 {D}/마디' if D else ''))
    if not a['solvable']:
        print(f'     그대로 두면: {d[0]}  | 풀리지 않아요')
        return dict(ok=False)
    capped = analyse(st, R, S, D, cap=a['min_edits'])
    g, n1 = first_move_rate(st, R, S, D)
    lost_best = a['full_hp'] - a['best_hp']
    lost_capped = a['full_hp'] - capped['best_hp']
    clash = '부딪혀요' if lost_capped > lost_best else '같이 돼요'
    print(f'     그대로 두면: {d[0]} | 최소 마디 {a["min_rounds"]} | 첫 수 성공 {g}/{n1} | 무작위 승률 {a["random_win"]:.1%}')
    print(f'     ★2 지휘 {a["min_edits"]}번 이하 | ★3 잃은 체력 {lost_best} 이하 | 지휘 {a["min_edits"]}번만 쓰면 최소 {lost_capped} 잃음 → 별 2·3 {clash} | 배우는 것: {lesson}')
    if trace:
        for r, base, chosen, c, log in find_plan(st, R, S, D):
            print(f'     [{r}마디] 기본 {" ".join(base)}\n             → {" ".join(chosen)}  (지휘 {c}번)')
            for line in log: print(f'               {line}')
    return dict(ok=ok, a=a, capped=capped, first=(g, n1), default=d)


def main(argv):
    trace = '--trace' in argv
    party_override = None
    if '--party' in argv:
        party_override = argv[argv.index('--party') + 1].split(',')
    pick = {int(a) for a in argv if a.isdigit()}
    for n, (title, parties, enemies, R, S, D, lesson) in enumerate(BATTLES, 1):
        if pick and n not in pick: continue
        for party in ([party_override] if party_override else parties):
            check(n, title, party, enemies, R, S, D, lesson, trace)
            sys.stdout.flush()


if __name__ == '__main__':
    main(sys.argv[1:])
