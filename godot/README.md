# 떠돌이 사냥꾼 — Godot 4 버전

웹 프로토타입(`../hunter.html`)을 **Godot 엔진**으로 새로 만든 버전이에요.
리듬 전투를 중심으로, 넓은 필드·채집·마을(잡화점/대장간/도박장/뽑기 신전)이 모두 들어 있어요.

## 여는 법 (계정 가입 필요 없음)

1. <https://godotengine.org/download> 에서 **Godot 4.3** (Standard, GDScript) 를 받아요. 설치 없이 압축만 풀면 돼요.
2. Godot를 켜고 **가져오기(Import)** → 이 `godot` 폴더 안의 `project.godot` 를 골라요.
3. 처음 열 때 그림·소리를 불러오느라 조금 걸려요. 끝나면 오른쪽 위 **▶ (F5)** 로 실행!

## 조작

| 어디서 | 키 | 하는 일 |
|---|---|---|
| 필드 | WASD / 방향키, 땅 클릭 | 이동 (Shift 달리기) |
| 필드 | 클릭 또는 가까이서 Space | 채집 · 몬스터와 전투 · 건물 들어가기 |
| 필드 | Q / I / H | 물약 / 가방 / 마을로 귀환 |
| 전투 | J (또는 Space, Z) | 공격 — 빨간 음표는 탭, 노란 막대는 끝까지 꾹 |
| 전투 | — | 보라 가시(함정)는 누르면 안 돼요 |
| 전투 | K (또는 X) | 방어 — 고리가 사냥꾼에게 닿는 순간. 딱 맞추면 반격(PARRY) |
| 전투 | Q / Esc | 물약 / 도망 |

터치 화면에서는 전투 아래 큰 **공격 / 방어** 버튼을 눌러요.

## 폴더 구조

```
godot/
  project.godot          프로젝트 설정 (화면 1280×720, 늘어나는 화면 지원)
  scenes/                title(첫 화면) · world(필드) · battle(전투)
  scripts/
    game.gd   (자동 로드) 데이터·저장·능력치·부적·지도 판정
    res.gd    (자동 로드) 스프라이트 시트·효과음 불러오기
    world.gd             필드: 땅, 채집 자원, 건물, 플레이어, 몬스터 생성
    monster.gd           몬스터 AI (돌아다니기/쫓기/도망)
    battle.gd            리듬 전투 (음악 박자 맞추기, 악보, 판정, 연출)
    hud.gd, minimap.gd   화면 정보
    panels.gd            상점·대장간·도박장·뽑기·가방·도움말 창
  shaders/               땅(물결·바닥 무늬) · 몬스터 번쩍임/테두리
  assets/                그림·소리·데이터 (아래 '에셋 다시 굽기')
  tests/autotest.tscn    개발용 자동 점검 (스크린샷 + 봇 전투)
```

## 에셋 다시 굽기

그림(몬스터 13종, 사냥꾼, 나무·바위·건물, 전투 배경), 땅 지도, 몬스터별 노래(OGG), 효과음, 악보는
웹 프로토타입의 코드로 그린 것을 `tools/bake/bake.js` 가 파일로 구워요.

```
npm i playwright        # 한 번만
node tools/bake/bake.js all      # 또는 creatures | hero | props | bg | terrain | audio | data
```

(ffmpeg 가 있어야 OGG 를 만들 수 있어요.)

## 내보내기 (다른 사람이 해 볼 수 있게)

Godot 메뉴 **프로젝트 → 내보내기** 에서 Windows / Web(HTML5) / Android 템플릿을 받아 내보낼 수 있어요.
웹으로 내보내면 itch.io 같은 곳에 무료로 올려 친구들이 브라우저로 해 볼 수 있어요.
돈을 받고 팔거나 광고를 넣는 건 보호자와 함께 해요.

## 글꼴

나눔고딕(NanumGothic, SIL Open Font License) — `assets/fonts/LICENSE.txt`
