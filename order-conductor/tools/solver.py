#!/usr/bin/env python3
"""순서 지휘자 v3 — 진형 + 사거리 + 대상 고르기 퍼즐. 규칙 시뮬레이터 + 판 검사기.

규칙 요약 (자세한 건 ../DESIGN.md)
- 줄: 아군 [1번(맨 앞) … 맨 뒤], 적 [1번 … 맨 뒤]. 아군 i번과 적 j번 사이 거리 = i + j - 1 (1번끼리 1칸).
- 마디마다 플레이어는 아군끼리 자리를 맞바꾸고(마디당 횟수 제한), 공격하는 아군(기사·궁수)의 대상을
  사거리 안의 적 중에서 골라요. 쉬게 할 수도 있어요.
- 시작하면 모두 '동시에' 행동해요. 대상은 마디 시작 때의 자리와 체력으로 정해요.
- 새 체력 = min(최대, 체력 + 회복) - 피해. 0 이하면 쓰러져요.
- 폭탄벌레는 쓰러지거나 도화선이 다 타면 (마디 끝) 그 자리에서 터져 양옆에 4. 연쇄 가능.
- 아군이 한 명이라도 쓰러지면 실패, 적이 모두 쓰러지면 승리 (둘 다면 실패).

    python3 solver.py              # 판 전부 검사
    python3 solver.py --trace 5    # 5번 판 풀이를 마디마다
"""
import itertools
import sys

# 이름: (편, 체력, 수치, 습관, 사거리 최소, 사거리 최대, 도화선)
UNITS = {
    '기사':     ('A', 10, 3, 'strike', 1, 2, 0),   # 고른 적에게 3 (사거리 1~2)
    '궁수':     ('A', 5, 2, 'strike', 2, 4, 0),    # 고른 적에게 2 (사거리 2~4, 바로 앞은 못 쏴요)
    '사제':     ('A', 6, 3, 'mend', 0, 1, 0),      # 자기·바로 옆 아군 중 가장 많이 다친 쪽 3 회복
    '방패병':   ('A', 12, 0, 'guard', 0, 0, 0),    # 1번 자리면: 자기에게 닿는 적의 한 명 노리기 공격을 모두 대신 맞아요
    '고블린':   ('E', 6, 3, 'near', 1, 2, 0),      # 사거리 안 가장 가까운 아군에게 3
    '해골궁수': ('E', 3, 3, 'weakest', 2, 5, 0),   # 사거리 안 체력이 가장 낮은 아군에게 3
    '폭탄벌레': ('E', 3, 4, 'bomb', 0, 0, 2),      # 도화선 2마디. 터지면 양옆에 4
    '주술사':   ('E', 4, 2, 'heal', 0, 99, 0),     # 가장 많이 다친 적(자기 포함) 2 회복
    '트롤':     ('E', 14, 4, 'cleave', 1, 2, 0),   # 사거리 안 아군 모두에게 4 (휩쓸기)
}

def side(u): return UNITS[u[0]][0]
def maxhp(u): return UNITS[u[0]][1]
def power(u): return UNITS[u[0]][2]
def habit(u): return UNITS[u[0]][3]
def reach(u): return UNITS[u[0]][4], UNITS[u[0]][5]
def dist(i, j): return i + j + 1          # 0부터 센 아군 i, 적 j
def in_range(u, d): lo, hi = reach(u); return lo <= d <= hi


def make(allies, enemies):
    """allies, enemies: 앞 → 뒤 순서. 상태 = (아군 앞→뒤, 적 앞→뒤, 체력표, 도화선표)."""
    A = tuple((n, i) for i, n in enumerate(allies))
    E = tuple((n, 10 + i) for i, n in enumerate(enemies))
    hp = tuple(sorted((u, maxhp(u)) for u in A + E))
    fuse = tuple(sorted((u, UNITS[u[0]][6]) for u in E if habit(u) == 'bomb'))
    return (A, E, hp, fuse)


def targets_for(state, A, u):
    """아군 공격수 u 가 지금 자리에서 고를 수 있는 적들 (가까운 순)."""
    E = state[1]; i = A.index(u)
    return [e for j, e in enumerate(E) if in_range(u, dist(i, j))]


def auto_target(state, A, u):
    """고르지 않았을 때의 기본 대상: 기사는 가장 가까운 적, 궁수는 가장 먼 적."""
    ts = targets_for(state, A, u)
    if not ts: return None
    return ts[0] if UNITS[u[0]][4] <= 1 else ts[-1]


def strikers(A): return [u for u in A if habit(u) == 'strike']


def target_choices(state, A):
    """공격수마다 (사거리 안 적들 + 쉬기)를 고르는 모든 조합."""
    S = strikers(A)
    opts = [targets_for(state, A, u) + [None] for u in S]
    return [dict(zip(S, combo)) for combo in itertools.product(*opts)]


def plan(state, A, T):
    """자리 A(앞→뒤)와 대상 T({공격수: 적 또는 None})로 각 유닛이 할 일. [(유닛, 종류, 대상들, 수치)]"""
    _, E, hp, _ = state
    hp = dict(hp)
    acts = []
    guard = A[0] if A and habit(A[0]) == 'guard' else None
    for i, u in enumerate(A):
        h = habit(u)
        if h == 'strike':
            t = T.get(u)
            if t is not None and t in E and in_range(u, dist(i, E.index(t))):
                acts.append((u, 'hit' if reach(u)[0] <= 1 else 'shoot', (t,), power(u)))
            else:
                acts.append((u, 'idle', (), 0))
        elif h == 'mend':
            near = [x for k, x in enumerate(A) if abs(k - i) <= 1]
            hurt = [x for x in near if hp[x] < maxhp(x)]
            if hurt:
                t = max(hurt, key=lambda x: (maxhp(x) - hp[x], -A.index(x)))
                acts.append((u, 'heal', (t,), power(u)))
            else:
                acts.append((u, 'rest', (), 0))
        elif h == 'guard':
            acts.append((u, 'guard', (u,), 0) if i == 0 else (u, 'idle', (), 0))
    for j, u in enumerate(E):
        h = habit(u)
        reachable = [x for k, x in enumerate(A) if in_range(u, dist(k, j))]
        if h in ('near', 'weakest'):
            if not reachable:
                acts.append((u, 'idle', (), 0)); continue
            if guard and guard in reachable: t = guard
            elif h == 'near': t = reachable[0]
            else: t = min(reachable, key=lambda x: (hp[x], A.index(x)))
            acts.append((u, 'hit' if h == 'near' else 'shoot', (t,), power(u)))
        elif h == 'cleave':
            acts.append((u, 'cleave', tuple(reachable), power(u)) if reachable else (u, 'idle', (), 0))
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


def run_round(state, A, T, log=None):
    """자리 A(앞→뒤), 대상 T 로 한 마디. 반환: (새 상태, 'win'|'lose'|None)."""
    _, E, hp0, fuse0 = state
    hp = dict(hp0); fuse = dict(fuse0)
    acts = plan(state, A, T)
    dmg = {u: 0 for u in hp}; heal = {u: 0 for u in hp}
    for u, kind, targets, n in acts:
        if kind in ('hit', 'shoot', 'cleave'):
            for t in targets: dmg[t] += n
        elif kind == 'heal':
            heal[targets[0]] += n
        if log is not None:
            log.append(f'{u[0]} {kind}' + (f' → {",".join(t[0] for t in targets)} {n}' if targets and n else ''))
    new = {u: min(maxhp(u), hp[u] + heal[u]) - dmg[u] for u in hp}
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


def choices(state, swaps):
    """한 마디에 고를 수 있는 (자리, 대상, 이동 수) 전부."""
    out = []
    for A, c in moves(state[0], swaps).items():
        for T in target_choices(state, A): out.append((A, T, c))
    return out


def analyse(state, rounds, swaps, cap=None):
    memo = {}
    def go(st, r, left):
        k = (st, r, left)
        if k in memo: return memo[k]
        if r == 0: memo[k] = (None, None, 0.0, None); return memo[k]
        opts = [(A, T, c) for A, T, c in choices(st, swaps) if left is None or c <= left]
        br = be = bh = None; p = 0.0
        for A, T, c in opts:
            nst, res = run_round(st, A, T)
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


def ally_hp(state):
    d = dict(state[2]); return sum(d[u] for u in state[0])


def auto_targets(state, A):
    return {u: auto_target(state, A, u) for u in strikers(A)}


def default_play(state, rounds):
    """자리도 그대로, 대상도 기본값 그대로."""
    st = state
    for r in range(rounds):
        st, res = run_round(st, st[0], auto_targets(st, st[0]))
        if res: return res, r + 1
    return 'timeout', rounds


def first_move_rate(state, rounds, swaps):
    good = 0; opts = choices(state, swaps)
    for A, T, c in opts:
        nst, res = run_round(state, A, T)
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
        # 같은 자리라면 기본 대상과 같은 쪽을 먼저 (플레이어 손이 덜 가는 풀이)
        opts = sorted(choices(state, swaps), key=lambda x: (x[2], x[0], sum(1 for u, t in x[1].items() if t != auto_target(state, x[0], u)), str(sorted(x[1].items()))))
        for A, T, c in opts:
            if c > left: continue
            nst, res = run_round(state, A, T)
            if (res == 'win' and ally_hp(nst) >= want) or (res is None and (analyse(nst, rounds - r - 1, swaps, cap=left - c)['best_hp'] or -1) >= want):
                log = []; run_round(state, A, T, log)
                out.append((A, T, c, log)); state, left = nst, left - c
                break
        if res == 'win': break
    return out


# 판: (제목, 아군 앞→뒤, 적 앞→뒤, 마디, 마디당 바꾸기, 배우는 것)
BATTLES_OLD = [
    ('첫 줄',       ['궁수', '기사', '사제'], ['해골궁수', '고블린'],              3, 1, '기사는 맨 앞에서만 칼이 닿아요'),
    ('옆을 지켜요', ['궁수', '기사', '사제'], ['고블린', '고블린'],                3, 1, '사제는 바로 옆만 고쳐요'),
    ('폭탄벌레',    ['궁수', '기사', '사제'], ['고블린', '폭탄벌레', '해골궁수'],    3, 1, '도화선이 다 타면 양옆이 맞아요'),
    ('주술사',      ['궁수', '기사', '사제'], ['고블린', '주술사'],                 3, 1, '회복보다 빨리 몰아쳐요'),
    ('방패병',      ['궁수', '사제', '기사', '방패병'], ['해골궁수', '해골궁수'],      3, 1, '방패병은 맨 앞에서 다 막아요'),
    ('트롤',        ['방패병', '기사', '궁수', '사제'], ['트롤', '폭탄벌레'],         3, 1, '휩쓸기는 1, 2번 자리를 함께 쳐요'),
    ('폭탄 앞줄',   ['기사', '궁수', '사제'], ['폭탄벌레', '고블린', '해골궁수'],    3, 1, '터지는 마디에 누가 맨 앞일까'),
    ('마지막 곡',   ['방패병', '기사', '궁수', '사제'], ['트롤', '폭탄벌레', '해골궁수'], 3, 1, '자리를 돌려 가며 버티기'),
]

BATTLES = [
    ('첫 줄',       ['궁수', '기사', '사제'], ['고블린', '해골궁수'],               3, 1, '기사는 앞에, 궁수는 한 칸 뒤에'),
    ('노릴 적',     ['기사', '궁수', '사제'], ['고블린', '주술사', '해골궁수'],      3, 1, '누구부터 쓰러뜨릴지 골라요'),
    ('사거리',      ['기사', '사제', '궁수'], ['주술사', '고블린', '해골궁수'],      3, 1, '사거리 안에서 노릴 적을 골라요'),
    ('옆을 지켜요', ['궁수', '기사', '사제'], ['고블린', '고블린'],                 3, 1, '사제는 바로 옆만 고쳐요'),
    ('폭탄벌레',    ['궁수', '기사', '사제'], ['폭탄벌레', '고블린', '해골궁수'],    3, 1, '폭탄을 일부러 터뜨려 적을 함께 날려요'),
    ('방패병',      ['사제', '궁수', '기사', '방패병'], ['해골궁수', '해골궁수'],    4, 1, '방패병은 닿는 화살을 다 막아요'),
    ('트롤',        ['방패병', '기사', '궁수', '사제'], ['폭탄벌레', '해골궁수', '트롤'], 3, 1, '휩쓸기는 사거리 안 모두를 쳐요'),
    ('마지막 곡',   ['궁수', '사제', '기사', '방패병'], ['고블린', '폭탄벌레', '트롤'],   3, 1, '지금까지 배운 것 전부'),
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
        for A, T, c, log in find_plan(st, R, S):
            tt = ", ".join(f"{u[0]}→{t[0] if t else '쉼'}" for u, t in T.items())
            print(f'     자리 {"·".join(u[0] for u in A)} (이동 {c}) 대상 {tt}')
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
