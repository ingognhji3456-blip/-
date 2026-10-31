# 순서 지휘자

아군도 적도 알아서 싸워요. 내가 정하는 건 **아군을 어느 자리에 세울지**와 **기사·궁수가 누구를 노릴지**뿐인 진형 퍼즐이에요.
`index.html` 하나로 돌아가요. 브라우저로 열면 바로 시작해요. 캐릭터는 직접 찍은 도트 그림이고, 동작마다 프레임 애니메이션이 있어요.

## 하는 법

- 아군(왼쪽)과 적(오른쪽)이 한 줄로 서요. 양쪽 1번 자리끼리 맞닿아 있고, 거리는 `아군 자리 + 적 자리 − 1`칸이에요.
- **아군 둘을 차례로 탭**하면 자리가 바뀌어요. 마디마다 옮길 수 있는 횟수가 있고, 다음 마디에 다시 채워져요.
- **기사·궁수를 탭한 뒤 적을 탭**하면 노릴 적을 골라요. 사거리 안의 적만 고를 수 있어요(초록 테두리). 지금 대상을 다시 탭하면 쉬어요.
  - 기사 1~2칸, 궁수 2~4칸(바로 앞은 못 쏴요). 적도 사거리가 있어요: 고블린 1~2칸, 해골궁수 2~5칸, 트롤 1~2칸 휩쓸기.
- **시작 ▶** 을 누르면 모두 **동시에** 행동해요. 그래서 화살표와 체력 막대에 이번 마디 결과가 미리 보여요.
- 적을 모두 쓰러뜨리면 승리, **아군이 한 명이라도 쓰러지면 실패**예요. 되돌리기는 마음껏 써도 돼요.
- 별 3개: ★ 클리어 · ★ 자리 이동 합을 기준 이하로 · ★ 잃은 체력을 기준 이하로.

## 파일

| 파일 | 하는 일 |
|---|---|
| `index.html` | 게임 전체 |
| `DESIGN.md` | 설계 문서 (규칙, 유닛, 판, 화면, 검증 기록) |
| `tools/solver.py` | 판 검사기: 판이 풀리는지, 별 기준값, 난이도를 계산해요 |
| `tools/parity_cases.py`, `tools/parity_test.mjs` | 게임의 규칙 엔진이 검사기와 한 줄도 안 틀리게 똑같은지 대조해요 |
| `tools/plans.py`, `tools/e2e.mjs` | 브라우저에서 8판을 실제로 클릭해서 깨 보고 별이 맞게 나오는지 확인해요 |
| `art/cast.js` | 캐릭터 9명의 도트 그림 원본과 애니메이션(칸마다 자세) |
| `art/raster.js`, `art/show.js`, `art/frames.js`, `art/export.js` | 도트 그림을 칸으로 바꾸기, 미리보기·애니메이션 칸 보기, `index.html`에 넣기 |

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
