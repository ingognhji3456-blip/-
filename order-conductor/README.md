# 순서 지휘자

아군도 적도 알아서 싸워요. 내가 할 수 있는 건 **누가 먼저 움직일지 차례를 바꾸는 것**뿐인 턴 순서 퍼즐이에요.
`index.html` 하나로 돌아가요. 브라우저로 열면 바로 시작해요.

## 하는 법

- 아군(왼쪽)과 적(오른쪽)이 한 줄로 서요. 모두 자기 **습관**대로만 움직여요(예: 기사는 맨 앞 적을, 해골궁수는 체력이 가장 낮은 아군을).
- 아래 **순서표**의 왼쪽부터 차례대로 움직여요. 마디(턴)마다 순서표는 **빠른 순**으로 새로 짜여요.
- 시작 전에 순서표에서 **두 명을 차례로 탭**하면 둘의 차례가 바뀌어요. 적의 차례도 바꿀 수 있어요.
  - 바꿀 수 있는 횟수는 판마다 정해져 있고, 마디마다 다시 채워져요.
  - 바꾼 둘을 다시 바꾸면 횟수를 돌려받아요.
- 유닛이나 초상화를 탭하면 **지금 차례가 오면 무엇을 할지** 화살표와 글로 보여요. 유닛 아래 작은 칸에도 늘 짧게 나와요.
- 적을 모두 쓰러뜨리면 승리예요. **아군이 한 명이라도 쓰러지면 실패**예요. 되돌리기는 마음껏 써도 돼요.
- 별 3개: ★ 클리어 · ★ 지휘(바꾼 횟수 합)를 목표 이하로 · ★ 잃은 체력을 목표 이하로. 두 별을 한 번에 받기 어려운 판도 있어요.
- 8판이에요. 6판부터는 맨 뒤 동료를 사제와 방패병 중에서 골라요.

## 파일

| 파일 | 하는 일 |
|---|---|
| `index.html` | 게임 전체 |
| `DESIGN.md` | 설계 문서 (규칙, 유닛, 판, 화면, 검증 기록) |
| `tools/solver.py` | 판 검사기: 판이 풀리는지, 별 기준값, 난이도를 계산해요 |
| `tools/parity_cases.py`, `tools/parity_test.mjs` | 게임의 규칙 엔진이 검사기와 한 줄도 안 틀리게 똑같은지 대조해요 |
| `tools/plans.py`, `tools/e2e.mjs` | 브라우저에서 8판을 실제로 클릭해서 깨 보고 별이 맞게 나오는지 확인해요 |
| `art/cast.js` | 캐릭터 9명의 도트 그림 원본 (모양으로 윤곽을 잡고 한 칸씩 덧칠) |
| `art/raster.js`, `art/show.js`, `art/export.js` | 도트 그림을 칸으로 바꾸기, 미리보기 그리기, `index.html`에 넣기 |

## 판이나 수치를 바꿀 때

1. `tools/solver.py`의 `UNITS`나 `BATTLES`를 고치고 검사기를 돌려요. 풀리는지, 별 기준값이 얼마인지 나와요.

   ```bash
   python3 order-conductor/tools/solver.py
   ```

2. 같은 값을 `index.html`의 `UNITS`(ENGINE 블록)와 `BATTLES`(DATA 블록)에 옮겨요.
3. 엔진 대조 테스트를 돌려요.

   ```bash
   python3 order-conductor/tools/parity_cases.py > /tmp/oc_cases.json
   ```

   ```bash
   node order-conductor/tools/parity_test.mjs /tmp/oc_cases.json
   ```

4. 브라우저 테스트를 돌려요. 스크린샷 폴더는 빼도 돼요.

   ```bash
   python3 order-conductor/tools/plans.py > /tmp/oc_plans.json
   ```

   ```bash
   node order-conductor/tools/e2e.mjs /tmp/oc_plans.json /tmp/oc-shots
   ```

## 캐릭터 그림을 고칠 때

1. `art/cast.js`에서 그 캐릭터를 고쳐요.
2. 미리보기를 그려서 확인해요. `GRID=1 BIG=8`을 앞에 붙이면 칸이 보이게 크게 그려요.

   ```bash
   node order-conductor/art/show.js /tmp/preview.png 기사 고블린
   ```

3. 게임에 넣어요. `index.html`의 ART 블록이 새로 바뀌어요.

   ```bash
   node order-conductor/art/export.js
   ```
