extends Node
## 게임 전체 상태: 데이터(game.json), 저장, 능력치, 입력 키

var D: Dictionary = {}
var S: Dictionary = {}
var in_battle := false
var sound_on := true
const SAVE_PATH := "user://save.json"

func _ready() -> void:
	for c in CHARMS:
		CHARM_BY[c.id] = c
	var f := FileAccess.open("res://assets/data/game.json", FileAccess.READ)
	D = JSON.parse_string(f.get_as_text())
	_setup_input()
	load_game()

func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"attack": [KEY_J, KEY_Z, KEY_SPACE], "defend": [KEY_K, KEY_X], "potion": [KEY_Q], "flee": [KEY_ESCAPE],
		"sprint": [KEY_SHIFT], "home": [KEY_H], "confirm": [KEY_ENTER, KEY_SPACE],
	}
	for a in map:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in map[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)

func default_save() -> Dictionary:
	return {"gold": 30, "hp": 60, "lv": 1, "xp": 0, "weapon": 0, "armor": 0, "tool": 0, "potions": 3,
		"mats": {}, "charms": {}, "equip": [], "pulls": 0, "pity": 0, "won": 0, "lost": 0,
		"x": D.world.cx, "y": D.world.cy + 70, "kills": 0, "best_combo": 0, "seen_help": false}

func load_game() -> void:
	S = default_save()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				S[k] = d[k]
	for k in ["gold", "lv", "xp", "weapon", "armor", "tool", "potions", "kills", "best_combo", "pulls", "pity", "won", "lost"]:
		S[k] = int(S[k])
	for k in S.charms:
		S.charms[k] = int(S.charms[k])
	S.equip = S.equip.filter(func(id): CHARM_BY.has(id) and S.charms.has(id))
	refresh_stats()

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(S))

func reset_game() -> void:
	S = default_save()
	refresh_stats()
	save_game()

# ---- 부적 (뽑기) ----
const RAR := ["N", "R", "SR", "SSR"]
const RAR_COL := ["b8c0cc", "5fb4ff", "c77dff", "ffcf4a"]
const CHARMS := [
	{"id": "leaf", "n": "네잎 부적", "r": 0, "eff": {"gather": 0.1}},
	{"id": "coin", "n": "동전 부적", "r": 0, "eff": {"gold": 0.06}},
	{"id": "feather", "n": "깃털 부적", "r": 0, "eff": {"spd": 0.06}},
	{"id": "shield", "n": "나무 방패", "r": 0, "eff": {"hp": 12}},
	{"id": "blade", "n": "칼날 조각", "r": 0, "eff": {"atk": 0.06}},
	{"id": "bell", "n": "박자 방울", "r": 1, "eff": {"win": 0.12}},
	{"id": "lucky", "n": "행운 동전", "r": 1, "eff": {"gold": 0.14}},
	{"id": "hunter", "n": "사냥꾼 표식", "r": 1, "eff": {"atk": 0.14}},
	{"id": "turtle", "n": "거북 등껍질", "r": 1, "eff": {"dr": 0.08}},
	{"id": "wind", "n": "바람 깃", "r": 1, "eff": {"spd": 0.14}},
	{"id": "metro", "n": "메트로놈", "r": 2, "eff": {"win": 0.25}},
	{"id": "fang", "n": "흡혈 송곳니", "r": 2, "eff": {"steal": 2}},
	{"id": "sack", "n": "풍요의 자루", "r": 2, "eff": {"dbl": 0.2}},
	{"id": "crown", "n": "황금 왕관", "r": 2, "eff": {"gold": 0.3}},
	{"id": "heart", "n": "용의 심장", "r": 3, "eff": {"atk": 0.35, "hp": 40}},
	{"id": "fortune", "n": "행운의 여신", "r": 3, "eff": {"gold": 0.35, "luck": 0.05}},
	{"id": "spirit", "n": "숲의 정령", "r": 3, "eff": {"pet": 1}},
]
var CHARM_BY := {}
const CHARM_MAX := 5
const REFUND := [20, 50, 150, 600]
const GACHA_COST := 100
const GACHA10 := 900
const PITY := 60
const POTION_COST := 20

func eff_text(eff: Dictionary, m: float) -> String:
	var out: Array[String] = []
	for k in eff:
		var v: float = eff[k]
		var pc := "%d%%" % roundi(v * m * 100)
		match k:
			"atk": out.append("공격력 +" + pc)
			"gold": out.append("골드 +" + pc)
			"gather": out.append("채집 힘 +" + pc)
			"spd": out.append("이동 속도 +" + pc)
			"hp": out.append("최대 체력 +%d" % roundi(v * m))
			"win": out.append("판정 범위 +" + pc)
			"dr": out.append("받는 피해 -" + pc)
			"steal": out.append("퍼펙트마다 체력 +%d" % roundi(v * m))
			"dbl": out.append("두 배 획득 +" + pc)
			"pet": out.append("정령이 자원을 저절로 채집 (×%.1f)" % m)
			"luck": out.append("도박 배당 +" + pc)
	return ", ".join(out)

# ---- 능력치 (장비 + 레벨 + 장착한 부적) ----
var ST := {}
func refresh_stats() -> void:
	var e := {"atk": 0.0, "gold": 0.0, "gather": 0.0, "spd": 0.0, "hp": 0.0, "win": 0.0, "dr": 0.0, "steal": 0.0, "dbl": 0.0, "pet": 0.0, "luck": 0.0}
	for id in S.equip:
		if not CHARM_BY.has(id):
			continue
		var lv := int(S.charms.get(id, 0))
		if lv <= 0:
			continue
		var m := 1.0 + 0.5 * (lv - 1)
		var c: Dictionary = CHARM_BY[id]
		for k in c.eff:
			e[k] += c.eff[k] * m
	ST = {
		"dmg": roundi((6 + 5 * S.weapon + 2 * (S.lv - 1)) * (1.0 + e.atk)),
		"max_hp": roundi(60 + 25 * S.armor + 8 * (S.lv - 1) + e.hp),
		"dr": minf(0.7, S.armor * 0.035 + e.dr),
		"power": (1.0 + S.tool) * (1.0 + e.gather),
		"extra": 1 if S.tool >= 4 else 0,
		"spd": 190.0 * (1.0 + e.spd), "win": 1.0 + e.win, "gold_mult": 1.0 + e.gold,
		"steal": e.steal, "dbl": e.dbl, "pet": e.pet, "luck": e.luck,
	}
	S.hp = minf(float(S.hp), ST.max_hp)

func max_hp() -> int:
	return ST.max_hp

func roll_rarity() -> int:
	S.pulls += 1
	S.pity += 1
	var r := 0
	if S.pity >= PITY:
		r = 3
	else:
		var x := randf() * 100.0
		r = 3 if x < 2 else 2 if x < 12 else 1 if x < 40 else 0
	if r == 3:
		S.pity = 0
	return r

## 등급 r의 부적을 하나 줘요. {c, note}
func grant(r: int) -> Dictionary:
	var pool := CHARMS.filter(func(c): return c.r == r)
	var c: Dictionary = pool.pick_random()
	var lv := int(S.charms.get(c.id, 0))
	var note := ""
	if lv == 0:
		S.charms[c.id] = 1
		note = "NEW!"
		if S.equip.size() < 3:
			S.equip.append(c.id)
			note = "NEW · 장착"
	elif lv < CHARM_MAX:
		S.charms[c.id] = lv + 1
		note = "Lv %d↑" % (lv + 1)
	else:
		S.gold += REFUND[r]
		note = "+%dG 환급" % REFUND[r]
	return {"c": c, "note": note}

func upgrade_cost(id: String) -> Dictionary:
	return D.upgrades[id].cost[S[id]]

func can_pay(c: Dictionary) -> bool:
	if S.gold < c.gold:
		return false
	for k in c.mats:
		if c.mats[k] and mat(k) < c.mats[k]:
			return false
	return true

func xp_need(lv: int) -> int:
	return int(round(20.0 * pow(1.35, lv - 1)))

## 경험치를 얻고 레벨이 오르면 올라간 횟수를 돌려줘요
func add_xp(n: int) -> int:
	S.xp += n
	var ups := 0
	while S.xp >= xp_need(S.lv):
		S.xp -= xp_need(S.lv)
		S.lv += 1
		ups += 1
	if ups > 0:
		refresh_stats()
		S.hp = max_hp()
	return ups

func add_mat(k: String, n: int) -> void:
	S.mats[k] = int(S.mats.get(k, 0)) + n

func mat(k: String) -> int:
	return int(S.mats.get(k, 0))

func mat_name(k: String) -> String:
	return D.mats[k].n if D.mats.has(k) else k

func fmt(n) -> String:
	var s := str(int(n))
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out

# ---- 지도: 지역·물 판정 (구워 둔 info.png / water.png) ----
var _info: Image
var _water: Image
const WG := 20.0

func _map_ready() -> void:
	if _info == null:
		_info = (load("res://assets/terrain/info.png") as Texture2D).get_image()
		_water = (load("res://assets/terrain/water.png") as Texture2D).get_image()
		if _info.is_compressed():
			_info.decompress()
		if _water.is_compressed():
			_water.decompress()

func zone_at(x: float, y: float) -> int:
	_map_ready()
	var n := _info.get_width()
	var s: float = D.world.size / float(n)
	var i := clampi(int(x / s), 0, n - 1)
	var j := clampi(int(y / s), 0, n - 1)
	return clampi(roundi(_info.get_pixel(i, j).r * 255.0 / 32.0), 0, 6)

func is_water(x: float, y: float) -> bool:
	_map_ready()
	var i := int(floor(x / WG))
	var j := int(floor(y / WG))
	if i < 0 or j < 0 or i >= _water.get_width() or j >= _water.get_height():
		return false
	return _water.get_pixel(i, j).r > 0.5

func near_water(x: float, y: float, r: float) -> bool:
	return is_water(x, y) or is_water(x + r, y) or is_water(x - r, y) or is_water(x, y + r) or is_water(x, y - r)

func walkable(x: float, y: float) -> bool:
	var w: float = D.world.size
	return x > 20 and x < w - 20 and y > 20 and y < w - 20 and not is_water(x, y)

func center() -> Vector2:
	return Vector2(D.world.cx, D.world.cy)

func zone_name(z: int) -> String:
	return ZONE_NAMES[z]

const ZONE_NAMES := ["평화로운 마을", "햇살 초원", "깊은 숲", "광산 폐허", "얼어붙은 설원", "타는 사막", "안개 늪"]
