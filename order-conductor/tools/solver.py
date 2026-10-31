#!/usr/bin/env python3
"""순서 지휘자 v2 — 진형 퍼즐 규칙 시뮬레이터 + 판 검사기.

규칙 요약 (자세한 건 ../DESIGN.md)
- 줄: 아군 [1번(맨 앞) … 맨 뒤], 적 [1번(맨 앞) … 맨 뒤]. 양쪽 1번끼리 맞닿아요.
- 마디마다 플레이어는 '아군끼리' 자리를 맞바꿔요 (마디당 횟수 제한). 바뀐 자리는 그대로 이어져요.
- 시작하면 모두 '동시에' 행동해요. 대상은 마디 시작 때의 자리와 체력으로 정해요.
- 피해와 회복을 한꺼번에 계산해요: 새 체력 = min(최대, 체력 + 회복) - 피해. 0 이하면 쓰러져요.
- 폭탄벌레는 쓰러지거나 도화선이 다 타면 (마디 끝) 그 자리에서 터져 양옆에 4. 연쇄 가능.
- 아군이 한 명이라도 쓰러지면 실패, 적이 모두 쓰러지면 승리 (둘 다면 실패).

    python3 solver.py              # 판 전부 검사
    python3 solver.py --trace 5    # 5번 판 풀이를 마디마다
"""
import itertools
import sys

# 이름: (편, 체력, 수치, 습관, 도화선)
UNITS = {
    '기사':     ('A', 10, 3, 'melee', 0),     # 1번 자리에서만: 적 1번에게 3
    '궁수':     ('A', 5, 2, 'archer', 0),     # 1번 자리가 아니면: 적 맨 뒤에게 2
    '사제':     ('A', 6, 3, 'mend', 0),       # 자기 + 바로 옆 아군 중 가장 많이 다친 쪽 3 회복
    '방패병':   ('A', 12, 0, 'guard', 0),     # 1번 자리면: 적의 '한 명 노리기' 공격을 모두 대신 맞아요
    '고블린':   ('E', 6, 3, 'reach2', 0),     # 적 1~2번 자리에서: 아군 1번에게 3
    '해골궁수': ('E', 3, 3, 'weakest', 0),    # 어디서든: 체력이 가장 낮은 아군에게 3
    '폭탄벌레': ('E', 3, 4, 'bomb', 2),       # 도화선 2마디. 터지면 양옆에 4
    '주술사':   ('E', 4, 2, 'heal', 0),       # 가장 많이 다친 적(자기 포함) 2 회복
    '트롤':     ('E', 14, 4, 'cleave', 0),    # 적 1번 자리에서만: 아군 1번과 2번에게 4씩
}

def side(u): return UNITS[u[0]][0]
def maxhp(u): return UNITS[u[0]][1]
def power(u): return UNITS[u[0]][2]
def habit(u): return UNITS[u[0]][3]


def make(allies, enemies):
    """allies, enemies: 앞 → 뒤 순서. 상태 = (아군 앞→뒤, 적 앞→뒤, 체력표, 도화선표)."""
    A = tuple((n, i) for i, n in enumerate(allies))
    E = tuple((n, 10 + i) for i, n in enumerate(enemies))
    hp = tuple(sorted((u, maxhp(u)) for u in A + E))
    fuse = tuple(sorted((u, UNITS[u[0]][4]) for u in E if habit(u) == 'bomb'))
    return (A, E, hp, fuse)


def plan(state, A):
    """자리(A: 앞→뒤)에서 각 유닛이 할 일. 반환: [(유닛, 종류, 대상들, 수치)]"""
    _, E, hp, _ = state
    hp = dict(hp)
    acts = []
    guard = A[0] if A and habit(A[0]) == 'guard' else None
    for i, u in enumerate(A):
        h = habit(u)
        if h == 'melee':
            acts.append((u, 'hit', (E[0],), power(u)) if i == 0 and E else (u, 'idle', (), 0))
        elif h == 'archer':
            acts.append((u, 'shoot', (E[-1],), power(u)) if i > 0 and E else (u, 'idle', (), 0))
        elif h == 'mend':
            near = [x for x in (A[i - 1] if i > 0 else None, u, A[i + 1] if i + 1 < len(A) else None) if x]
            near.sort(key=lambda x: A.index(x))
            hurt = [x for x in near if hp[x] < maxhp(x)]
            if hurt:
                t = max(hurt, key=lambda x: (maxhp(x) - hp[x], -A.index(x)))
                acts.append((u, 'heal', (t,), power(u)))
            else:
                acts.append((u, 'rest', (), 0))
        elif h == 'guard':
            acts.append((u, 'guard', (u,), 0) if i == 0 else (u, 'idle', (), 0))
    for i, u in enumerate(E):
        h = habit(u)
        if h == 'reach2':
            if i <= 1 and A:
                acts.append((u, 'hit', (guard or A[0],), power(u)))
            else:
                acts.append((u, 'idle', (), 0))
        elif h == 'weakest':
            if A:
                t = guard or min(A, key=lambda x: (hp[x], A.index(x)))
                acts.append((u, 'shoot', (t,), power(u)))
        elif h == 'cleave':
            acts.append((u, 'cleave', tuple(A[:2]), power(u)) if i == 0 and A else (u, 'idle', (), 0))
        elif h == 'heal':
            hurt = [x for x in E if hp[x] < maxhp(x)]
            if hurt:
                t = max(hurt, key=lambda x: (maxhp(x) - hp[x], -E.index(x)))
                acts.append((u, 'heal', (t,), power(u)))
            else:
                acts.append((u, 'rest', (), 0))
        elif h == 'bomb':
            acts.append((u, 'fuse', (), 0))
    return acts


def run_round(state, A, log=None):
    """자리 A(앞→뒤)로 한 마디. 반환: (새 상태, 'win'|'lose'|None)."""
    _, E, hp0, fuse0 = state
    hp = dict(hp0); fuse = dict(fuse0)
    acts = plan(state, A)
    dmg = {u: 0 for u in hp}; heal = {u: 0 for u in hp}
    for u, kind, targets, n in acts:
        if kind in ('hit', 'shoot', 'cleave'):
            for t in targets: dmg[t] += n
        elif kind == 'heal':
            heal[targets[0]] += n
        if log is not None:
            log.append(f'{u[0]} {kind}' + (f' → {",".join(t[0] for t in targets)} {n}' if targets and n else ''))
    new = {u: min(maxhp(u), hp[u] + heal[u]) - dmg[u] for u in hp}
    # 폭탄: 쓰러졌거나 도화선이 다 탄 폭탄이 터져요 (마디 시작 때 줄에서 양옆), 연쇄
    line = list(reversed(A)) + list(E)
    queue = [u for u in E if habit(u) == 'bomb' and (new[u] <= 0 or fuse[u] - 1 <= 0)]
    boomed = set()
    while queue:
        b = queue.pop(0)
        if b in boomed: continue
        boomed.add(b); new[b] = min(new[b], 0)
        p = line.index(b)
        near = [line[j] for j in (p - 1, p + 1) if 0 <= j < len(line)]
        if log is not None: log.append(f'{b[0]} 펑 → {",".join(t[0] for t in near)}')
        for t in near:
            if t in boomed: continue
            new[t] -= power(b)
            if habit(t) == 'bomb' and new[t] <= 0: queue.append(t)
    dead = {u for u in new if new[u] <= 0}
    if log is not None and dead: log.append('쓰러짐: ' + ','.join(sorted(u[0] for u in dead)))
    A2 = tuple(u for u in A if u not in dead)
    E2 = tuple(u for u in E if u not in dead)
    hp2 = tuple(sorted((u, v) for u, v in new.items() if u not in dead))
    fuse2 = tuple(sorted((u, fuse[u] - 1) for u in E2 if habit(u) == 'bomb'))
    if len(A2) < len(A): return (A2, E2, hp2, fuse2), 'lose'
    if not E2: return (A2, E2, hp2, fuse2), 'win'
    return (A2, E2, hp2, fuse2), None


_cache = {}
def moves(A, swaps):
    """지금 자리에서 바꾸기 swaps번 이하로 만들 수 있는 자리 → 최소 바꾸기 수."""
    key = (A, swaps)
    if key in _cache: return _cache[key]
    best = {A: 0}; frontier = [A]
    for d in range(1, swaps + 1):
        nxt = []
        for o in frontier:
            for i, j in itertools.combinations(range(len(o)), 2):
                l = list(o); l[i], l[j] = l[j], l[i]; t = tuple(l)
                if t not in best: best[t] = d; nxt.append(t)
        frontier = nxt
    _cache[key] = best
    return best


def ally_hp(state):
    d = dict(state[2]); return sum(d[u] for u in state[0])


def analyse(state, rounds, swaps, cap=None):
    memo = {}
    def go(st, r, left):
        k = (st, r, left)
        if k in memo: return memo[k]
        if r == 0: memo[k] = (None, None, 0.0, None); return memo[k]
        opts = [(A, c) for A, c in moves(st[0], swaps).items() if left is None or c <= left]
        br = be = bh = None; p = 0.0
        for A, c in opts:
            nst, res = run_round(st, A)
            if res == 'win': mr, me, q, mh = 1, c, 1.0, ally_hp(nst)
            elif res == 'lose': mr, me, q, mh = None, None, 0.0, None
            else:
                sr, se, q, sh = go(nst, r - 1, None if left is None else left - c)
                mr, me, mh = (None, None, None) if sr is None else (sr + 1, se + c, sh)
            if mr is not None:
                br = mr if br is None else min(br, mr)
                be = me if be is None else min(be, me)
                bh = mh if bh is None else max(bh, mh)
            p += q
        memo[k] = (br, be, p / len(opts), bh)
        return memo[k]
    r, e, p, h = go(state, rounds, cap)
    return dict(solvable=r is not None, min_rounds=r, min_moves=e, random_win=p, best_hp=h,
                full_hp=sum(maxhp(u) for u in state[0]))


def default_play(state, rounds):
    st = state
    for r in range(rounds):
        st, res = run_round(st, st[0])
        if res: return res, r + 1
    return 'timeout', rounds


def first_move_rate(state, rounds, swaps):
    good = 0; opts = moves(state[0], swaps)
    for A in opts:
        nst, res = run_round(state, A)
        if res == 'win' or (res is None and analyse(nst, rounds - 1, swaps)['solvable']): good += 1
    return good, len(opts)


def find_plan(state, rounds, swaps, mode='moves'):
    a = analyse(state, rounds, swaps)
    if mode == 'moves':
        cap = a['min_moves']; want = analyse(state, rounds, swaps, cap=cap)['best_hp']
    else:
        want = a['best_hp']
        cap = next(c for c in range(rounds * swaps + 1) if (analyse(state, rounds, swaps, cap=c)['best_hp'] or -1) >= want)
    out, left = [], cap
    for r in range(rounds):
        for A, c in sorted(moves(state[0], swaps).items(), key=lambda x: (x[1], x[0])):
            if c > left: continue
            nst, res = run_round(state, A)
            if (res == 'win' and ally_hp(nst) >= want) or (res is None and (analyse(nst, rounds - r - 1, swaps, cap=left - c)['best_hp'] or -1) >= want):
                log = []; run_round(state, A, log)
                out.append((A, c, log)); state, left = nst, left - c
                break
        if res == 'win': break
    return out


# 판: (제목, 아군 앞→뒤, 적 앞→뒤, 마디, 마디당 바꾸기, 배우는 것)
BATTLES = [
    ('첫 줄',       ['궁수', '기사', '사제'], ['해골궁수', '고블린'],              3, 1, '기사는 맨 앞에서만 칼이 닿아요'),
    ('옆을 지켜요', ['궁수', '기사', '사제'], ['고블린', '고블린'],                3, 1, '사제는 바로 옆만 고쳐요'),
    ('폭탄벌레',    ['궁수', '기사', '사제'], ['고블린', '폭탄벌레', '해골궁수'],    3, 1, '도화선이 다 타면 양옆이 맞아요'),
    ('주술사',      ['궁수', '기사', '사제'], ['고블린', '주술사'],                 3, 1, '회복보다 빨리 몰아쳐요'),
    ('방패병',      ['궁수', '사제', '기사', '방패병'], ['해골궁수', '해골궁수'],      3, 1, '방패병은 맨 앞에서 다 막아요'),
    ('트롤',        ['방패병', '기사', '궁수', '사제'], ['트롤', '폭탄벌레'],         3, 1, '휩쓸기는 1, 2번 자리를 함께 쳐요'),
    ('폭탄 앞줄',   ['기사', '궁수', '사제'], ['폭탄벌레', '고블린', '해골궁수'],    3, 1, '터지는 마디에 누가 맨 앞일까'),
    ('마지막 곡',   ['방패병', '기사', '궁수', '사제'], ['트롤', '폭탄벌레', '해골궁수'], 3, 1, '자리를 돌려 가며 버티기'),
]


def check(n, title, allies, enemies, R, S, lesson, trace=False):
    st = make(allies, enemies)
    a = analyse(st, R, S); d = default_play(st, R)
    print(f'{"OK " if a["solvable"] and d[0] != "win" else "!! "}{n}. {title}  아군={"·".join(allies)}  적={"·".join(enemies)}  마디 {R} · 바꾸기 {S}/마디')
    if not a['solvable']:
        print(f'     그대로 두면 {d}, 풀리지 않아요'); return a
    cap = analyse(st, R, S, cap=a['min_moves'])
    g, n1 = first_move_rate(st, R, S)
    lost, lost_c = a['full_hp'] - a['best_hp'], a['full_hp'] - cap['best_hp']
    print(f'     그대로 두면 {d[0]} | 최소 마디 {a["min_rounds"]} | 첫 수 성공 {g}/{n1} | 무작위 {a["random_win"]:.1%} | ★2 이동 {a["min_moves"]} | ★3 잃은 체력 {lost} (이동 최소일 땐 {lost_c}) | {lesson}')
    if trace:
        for A, c, log in find_plan(st, R, S):
            print(f'     자리 {"·".join(u[0] for u in A)} (이동 {c})')
            for l in log: print(f'        {l}')
    return a


def main(argv):
    trace = '--trace' in argv
    pick = {int(x) for x in argv if x.isdigit()}
    for n, (title, allies, enemies, R, S, lesson) in enumerate(BATTLES, 1):
        if pick and n not in pick: continue
        check(n, title, allies, enemies, R, S, lesson, trace); sys.stdout.flush()


if __name__ == '__main__':
    main(sys.argv[1:])
