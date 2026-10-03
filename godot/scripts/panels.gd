extends CanvasLayer
## 건물 안 창: 잡화점, 대장간, 도박장, 뽑기 신전, 가방, 도움말

const HUD := preload("res://scripts/hud.gd")
const MAT_COL := {"wood": "8a5a2e", "stone": "9a958a", "herb": "6fbf4a", "shroom": "c98a5a", "iron": "8a8f99", "crystal": "9fe6ff", "ice": "dff6ff",
	"cactus": "6fa34a", "goldnug": "ffd24a", "lotus": "ffb3d0", "goo": "9fe08a", "fur": "d8d0c2", "pelt": "8a6a4a", "tusk": "f0e8d0", "wing": "6a5a6a",
	"core": "b07cff", "toadskin": "7a8a3a", "lizscale": "4a9a6a", "sting": "c0a040", "wormshell": "d8b67a", "yfur": "f4f4f4", "frost": "9fd8ff", "scale": "c8452f"}
const SLOT := [["체리", 30, 8, 0, "ff4a5a"], ["레몬", 25, 12, 0, "ffe14a"], ["종", 18, 20, 0, "ffb84a"], ["별", 12, 40, 2, "fff07a"], ["보석", 6, 100, 4, "6ad8ff"], ["7", 3, 500, 8, "ff5a3a"]]
const TITLES := {"shop": "잡화점", "smith": "대장간", "casino": "도박장", "gacha": "뽑기 신전", "bag": "가방", "help": "떠돌이 사냥꾼"}

var w
var panel := ""
var busy := false
var dim: ColorRect
var win: PanelContainer
var title_l: Label
var close_b: Button
var body: VBoxContainer
var scroll: ScrollContainer
var casino_tab := "dice"
var bag_tab := "mats"
var bet := 10
var dice_view := [3, 4]
var slot_view := ["체리", "별", "7"]
var gamble_msg := ""
var gamble_col := Color.WHITE
var last_cards: Array = []
var _grid: GridContainer

class Dice extends Control:
	var n := 1
	var red := false
	func _init(v: int, r: bool) -> void:
		n = v
		red = r
		custom_minimum_size = Vector2(70, 70)
	func _draw() -> void:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("fff8ee")
		s.set_corner_radius_all(12)
		s.shadow_size = 4
		s.shadow_color = Color(0, 0, 0, 0.4)
		draw_style_box(s, Rect2(Vector2.ZERO, size))
		var on: Array = {1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8]}[n]
		for i in on:
			var p := Vector2(size.x * (0.25 + 0.25 * (i % 3)), size.y * (0.25 + 0.25 * (i / 3)))
			draw_circle(p, size.x * 0.085, Color("d8283a") if red else Color("222"))

func _ready() -> void:
	layer = 8
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and panel != "help":
			close())
	add_child(dim)
	win = PanelContainer.new()
	win.add_theme_stylebox_override("panel", HUD.box(Color(0.07, 0.08, 0.13, 0.97), 16, Color(1, 1, 1, 0.12)))
	add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	win.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title_l = HUD.mk_label("", 24, Color("ffe9b0"))
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_l)
	close_b = Button.new()
	close_b.text = "닫기 (Esc)"
	close_b.focus_mode = Control.FOCUS_NONE
	HUD.style_button(close_b)
	close_b.pressed.connect(close)
	head.add_child(close_b)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	visible = false
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var sz := Vector2(minf(600, vs.x - 24), minf(640, vs.y - 24))
	win.position = (vs - sz) / 2
	win.size = sz
	win.custom_minimum_size = sz

func is_open() -> bool:
	return panel != ""

func open(id: String) -> void:
	if w.battle:
		return
	panel = id
	w.P.move_to = null
	w.P.target = {}
	visible = true
	last_cards = []
	gamble_msg = ""
	_layout()
	render()

func close() -> void:
	if busy:
		return
	if panel == "help":
		Game.S.seen_help = true
	panel = ""
	visible = false
	w._save()

func _unhandled_input(e: InputEvent) -> void:
	if panel == "":
		return
	if e.is_action_pressed("flee") or (panel == "help" and e.is_action_pressed("confirm")):
		close()
		get_viewport().set_input_as_handled()

# ---------------- 그리기 도우미 ----------------
func _clear() -> void:
	for c in body.get_children():
		c.queue_free()

func _lbl(txt: String, size := 15, col := Color(0.85, 0.88, 0.94)) -> Label:
	var l := HUD.mk_label(txt, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_font_override("font", Res.font_bold)
	body.add_child(l)
	return l

func _btn(parent: Control, txt: String, cb: Callable, enabled := true, col := Color("2a3350"), size := 15) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	HUD.style_button(b, col, size)
	b.custom_minimum_size = Vector2(0, 40)
	b.disabled = not enabled or busy
	b.pressed.connect(func():
		if busy:
			return
		cb.call()
		Game.save_game()
		if not busy:
			render())
	parent.add_child(b)
	return b

func _row(parent: Control = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	(parent if parent else body).add_child(h)
	return h

func _card(col := Color(1, 1, 1, 0.05), border := Color(0, 0, 0, 0)) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HUD.box(col, 12, border))
	body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v

func _swatch(parent: Control, k: String) -> void:
	var c := ColorRect.new()
	c.color = Color(MAT_COL.get(k, "cccccc"))
	c.custom_minimum_size = Vector2(16, 16)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(c)

func _sub(parent: Control, txt: String, size := 14, col := Color(0.65, 0.7, 0.8)) -> Label:
	var l := HUD.mk_label(txt, size, col)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_font_override("font", Res.font_bold)
	if parent is VBoxContainer:  # 가로로 늘어놓는 칸에서는 줄바꿈하면 글자가 세로로 쪼개져요
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func render() -> void:
	if panel == "":
		return
	title_l.text = TITLES[panel]
	close_b.visible = panel != "help"
	_clear()
	call("_r_" + panel)

# ---------------- 도움말 ----------------
func _r_help() -> void:
	_lbl("넓은 들판을 돌아다니며 채집하고, 몬스터와 리듬 전투를 벌여요. 몬스터마다 노래가 달라요!", 16, Color.WHITE)
	var c := _card()
	_sub(c, "이동", 16, Color("ffe27a"))
	_sub(c, "WASD / 방향키 또는 땅을 클릭(터치). Shift를 누르면 달려요.")
	_sub(c, "채집·전투", 16, Color("ffe27a"))
	_sub(c, "나무·바위·약초를 클릭하거나 가까이서 Space. 몬스터를 클릭하거나 부딪히면 전투가 시작돼요.")
	var c2 := _card()
	_sub(c2, "리듬 전투", 16, Color("ff8a95"))
	_sub(c2, "빨간 음표가 원에 닿을 때 J(또는 Space) — 공격!")
	_sub(c2, "노란 막대는 끝날 때까지 꾹 누르기 — 마무리 일격!")
	_sub(c2, "보라 가시는 누르면 안 돼요 — 함정!")
	_sub(c2, "몬스터가 웅크리고 사냥꾼 둘레의 고리가 좁혀지면, 고리가 닿는 순간 K — 방어! 딱 맞추면 반격(PARRY).")
	_sub(c2, "체력이 절반 아래로 떨어지면 몬스터가 분노해서 음악이 거세져요.")
	var c3 := _card()
	_sub(c3, "마을", 16, Color("8ee6ff"))
	_sub(c3, "잡화점에서 재료를 팔고 물약을 사요. 대장간에서 장비를 강화하고, 뽑기 신전에서 부적을 모아요.")
	var r := _row()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn(r, "  시작하기 (Enter)  ", close, true, Color("c0392b"), 18)

# ---------------- 잡화점 ----------------
func _r_shop() -> void:
	var S := Game.S
	_lbl("재료를 팔아 골드를 벌어요. 가진 골드: %s G" % Game.fmt(S.gold))
	var c := _card()
	_sub(c, "체력 물약 — 가진 수 %d" % S.potions, 17, Color.WHITE)
	_sub(c, "최대 체력의 50%를 회복해요. 전투 중에도 Q로 마셔요.")
	var r := _row(c)
	_btn(r, "1개 · %dG" % Game.POTION_COST, func(): _buy_pot(1), S.gold >= Game.POTION_COST, Color("8a6a1e"))
	_btn(r, "5개 · %dG" % (Game.POTION_COST * 5), func(): _buy_pot(5), S.gold >= Game.POTION_COST * 5, Color("8a6a1e"))
	_lbl("재료 팔기", 17, Color.WHITE)
	var have := _have()
	if have.is_empty():
		_lbl("팔 재료가 없어요. 밖에서 채집하거나 사냥해 보세요.")
		return
	var total := 0
	for k in have:
		total += Game.mat(k) * int(Game.D.mats[k].p)
	var r2 := _row()
	var b := _btn(r2, "전부 팔기 · +%s G" % Game.fmt(total), _sell_all, true, Color("8a6a1e"), 16)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in have:
		var row := _row()
		_swatch(row, k)
		var l := _sub(row, "%s ×%d   (개당 %dG)" % [Game.mat_name(k), Game.mat(k), Game.D.mats[k].p], 15, Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_btn(row, "1개", func(): _sell(k, 1))
		_btn(row, "전부", func(): _sell(k, Game.mat(k)))

func _have() -> Array:
	var out := []
	for k in Game.D.mats:
		if Game.mat(k) > 0:
			out.append(k)
	return out

func _buy_pot(n: int) -> void:
	if Game.S.gold < Game.POTION_COST * n:
		return
	Game.S.gold -= Game.POTION_COST * n
	Game.S.potions += n
	Res.sfx("coin")

func _sell(k: String, n: int) -> void:
	n = mini(n, Game.mat(k))
	if n <= 0:
		return
	Game.S.mats[k] = Game.mat(k) - n
	Game.S.gold += n * int(Game.D.mats[k].p)
	Res.sfx("coin")

func _sell_all() -> void:
	var g := 0
	for k in Game.D.mats:
		g += Game.mat(k) * int(Game.D.mats[k].p)
		Game.S.mats[k] = 0
	Game.S.gold += g
	Res.sfx("coin")
	w.toast("재료를 모두 팔아 +%s G" % Game.fmt(g), "gold")

# ---------------- 대장간 ----------------
func _r_smith() -> void:
	var S := Game.S
	var ST := Game.ST
	_lbl("골드와 재료로 장비를 강화해요. 가진 골드: %s G" % Game.fmt(S.gold))
	for id in ["weapon", "armor", "tool"]:
		var u: Dictionary = Game.D.upgrades[id]
		var L: int = S[id]
		var c := _card()
		_sub(c, "%s  +%d / %d" % [u.n, L, u.max], 18, Color.WHITE)
		var now := ""
		var nxt := ""
		match id:
			"weapon":
				now = "공격력 %d" % ST.dmg
				nxt = "공격력 +5"
			"armor":
				now = "최대 체력 %d · 받는 피해 -%d%%" % [ST.max_hp, roundi(ST.dr * 100)]
				nxt = "최대 체력 +25, 받는 피해 -3.5%"
			"tool":
				now = "채집 힘 %.1f%s" % [ST.power, " · 채집량 +1" if S.tool >= 4 else ""]
				nxt = "채집 힘 +1, 채집량 +1" if S.tool == 3 else "채집 힘 +1"
		_sub(c, "지금: " + now)
		if L >= int(u.max):
			_sub(c, "최대 강화!", 15, Color("5fdc8a"))
			continue
		_sub(c, "다음: " + nxt)
		var cost: Dictionary = u.cost[L]
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		c.add_child(flow)
		_sub(flow, "골드 %s" % Game.fmt(cost.gold), 14, Color("5fdc8a") if S.gold >= cost.gold else Color("ff6b78"))
		for k in cost.mats:
			if cost.mats[k]:
				var ok: bool = Game.mat(k) >= cost.mats[k]
				_sub(flow, "%s %d/%d" % [Game.mat_name(k), Game.mat(k), cost.mats[k]], 14, Color("5fdc8a") if ok else Color("ff6b78"))
		var r := _row(c)
		var b := _btn(r, "강화하기", func(): _upgrade(id), Game.can_pay(cost), Color("c0392b"), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _upgrade(id: String) -> void:
	var u: Dictionary = Game.D.upgrades[id]
	var L: int = Game.S[id]
	if L >= int(u.max):
		return
	var c: Dictionary = u.cost[L]
	if not Game.can_pay(c):
		return
	Game.S.gold -= int(c.gold)
	for k in c.mats:
		Game.S.mats[k] = Game.mat(k) - int(c.mats[k])
	Game.S[id] += 1
	Game.refresh_stats()
	if id == "armor":
		Game.S.hp = Game.max_hp()
	Res.sfx("lvl")
	w.toast("%s +%d 강화 성공!" % [u.n, Game.S[id]], "good")

# ---------------- 도박장 ----------------
func _r_casino() -> void:
	var S := Game.S
	bet = clampi(bet, 1, maxi(1, S.gold))
	var tabs := _row()
	_btn(tabs, "홀짝 주사위", func(): _tab("dice"), true, Color("c0392b") if casino_tab == "dice" else Color("2a3350"))
	_btn(tabs, "슬롯머신", func(): _tab("slot"), true, Color("c0392b") if casino_tab == "slot" else Color("2a3350"))
	var br := _row()
	_btn(br, "−10", func(): bet = clampi(bet - 10, 1, maxi(1, S.gold)))
	var amt := _sub(br, "  건 돈 %s G  " % Game.fmt(bet), 18, Color("ffd24a"))
	amt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn(br, "+10", func(): bet = clampi(bet + 10, 1, maxi(1, S.gold)))
	_btn(br, "100", func(): bet = clampi(100, 1, maxi(1, S.gold)))
	_btn(br, "절반", func(): bet = clampi(S.gold / 2, 1, maxi(1, S.gold)))
	_btn(br, "올인", func(): bet = maxi(1, S.gold))
	_lbl("가진 골드: %s G" % Game.fmt(S.gold))
	var luck: float = Game.ST.luck
	if casino_tab == "dice":
		_lbl("주사위 두 개의 합이 홀수일까, 짝수일까? 맞히면 건 돈의 ×%.2f를 받아요." % (1.95 + luck))
		var st := _row()
		st.alignment = BoxContainer.ALIGNMENT_CENTER
		st.add_theme_constant_override("separation", 20)
		st.add_child(Dice.new(dice_view[0], true))
		st.add_child(Dice.new(dice_view[1], false))
		st.name = "stage"
		var res := _lbl(gamble_msg, 18, gamble_col)
		res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var r := _row()
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		_btn(r, "   홀   ", func(): _dice(true, st, res), S.gold >= 1, Color("c0392b"), 20)
		_btn(r, "   짝   ", func(): _dice(false, st, res), S.gold >= 1, Color("2a5aa8"), 20)
	else:
		var st := _row()
		st.alignment = BoxContainer.ALIGNMENT_CENTER
		st.add_theme_constant_override("separation", 12)
		var reels: Array[Label] = []
		for s in slot_view:
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", HUD.box(Color("1a1626"), 12, Color("ffd24a")))
			p.custom_minimum_size = Vector2(110, 80)
			var l := HUD.mk_label(s, 26, _slot_col(s))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			p.add_child(l)
			st.add_child(p)
			reels.append(l)
		var res := _lbl(gamble_msg, 18, gamble_col)
		res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var r := _row()
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		_btn(r, "   레버 당기기!   ", func(): _slot(reels, res), S.gold >= 1, Color("8a6a1e"), 20)
		var pay := HFlowContainer.new()
		pay.add_theme_constant_override("h_separation", 14)
		body.add_child(pay)
		for s in SLOT:
			_sub(pay, "%s×3 → ×%d" % [s[0], s[2]], 13, Color(s[4]))
		for s in SLOT:
			if s[3]:
				_sub(pay, "%s×2 → ×%d" % [s[0], s[3]], 13, Color(s[4]).darkened(0.2))
		if luck > 0:
			_lbl("행운의 여신: 배당 +%d%%" % roundi(luck * 100), 14, Color("ffe27a"))
	_lbl("지금까지 도박으로 딴 돈 %s · 잃은 돈 %s" % [Game.fmt(S.won), Game.fmt(S.lost)], 13, Color(0.6, 0.65, 0.75))
	_lbl("도박은 게임 속 골드로만 해요. 잃을 수 있는 만큼만 거세요!", 12, Color(0.55, 0.6, 0.7))

func _slot_col(s: String) -> Color:
	for r in SLOT:
		if r[0] == s:
			return Color(r[4])
	return Color.WHITE

func _tab(t: String) -> void:
	casino_tab = t
	gamble_msg = ""

func _lock_buttons() -> void:
	for b in body.find_children("*", "Button", true, false):
		b.disabled = true
	close_b.disabled = true

func _dice(odd_guess: bool, stage: HBoxContainer, res: Label) -> void:
	var S := Game.S
	if busy or S.gold < 1:
		return
	bet = clampi(bet, 1, S.gold)
	var b := bet
	S.gold -= b
	busy = true
	_lock_buttons()
	res.text = "데구르르…"
	res.add_theme_color_override("font_color", Color.WHITE)
	for k in 12:
		await get_tree().create_timer(0.07).timeout
		dice_view = [randi_range(1, 6), randi_range(1, 6)]
		for c in stage.get_children():
			c.queue_free()
		stage.add_child(Dice.new(dice_view[0], true))
		stage.add_child(Dice.new(dice_view[1], false))
		Res.sfx("sticks", -6.0, randf_range(0.8, 1.2))
	var sum: int = dice_view[0] + dice_view[1]
	var odd := sum % 2 == 1
	if odd == odd_guess:
		var g := int(b * (1.95 + Game.ST.luck))
		S.gold += g
		S.won += g - b
		gamble_msg = "%d (%s)! 맞혔어요 +%s G" % [sum, "홀" if odd else "짝", Game.fmt(g)]
		gamble_col = Color("5fdc8a")
		Res.sfx("coin")
		Res.sfx("win", -4.0)
	else:
		S.lost += b
		gamble_msg = "%d (%s)… %s G를 잃었어요" % [sum, "홀" if odd else "짝", Game.fmt(b)]
		gamble_col = Color("ff6b78")
		Res.sfx("miss")
	busy = false
	close_b.disabled = false
	Game.save_game()
	render()

func _slot(reels: Array[Label], res: Label) -> void:
	var S := Game.S
	if busy or S.gold < 1:
		return
	bet = clampi(bet, 1, S.gold)
	var b := bet
	S.gold -= b
	busy = true
	_lock_buttons()
	res.text = ""
	var total := 0
	for r in SLOT:
		total += r[1]
	var roll := func() -> String:
		var x := randf() * total
		for r in SLOT:
			x -= r[1]
			if x < 0:
				return r[0]
		return SLOT[0][0]
	var out := [roll.call(), roll.call(), roll.call()]
	var stops := [0.7, 1.05, 1.4]
	var el := 0.0
	var done := [false, false, false]
	while not done[2]:
		await get_tree().create_timer(0.06).timeout
		el += 0.06
		for i in 3:
			if done[i]:
				continue
			if el >= stops[i]:
				done[i] = true
				reels[i].text = out[i]
				Res.sfx("block", -4.0)
			else:
				reels[i].text = SLOT[randi() % SLOT.size()][0]
			reels[i].add_theme_color_override("font_color", _slot_col(reels[i].text))
		Res.sfx("sticks", -12.0, 1.4)
	slot_view = out
	var mult := 0
	if out[0] == out[1] and out[1] == out[2]:
		for r in SLOT:
			if r[0] == out[0]:
				mult = r[2]
	else:
		for r in SLOT:
			if r[3] and out.count(r[0]) == 2:
				mult = r[3]
	if mult:
		var g := int(b * mult * (1.0 + Game.ST.luck))
		S.gold += g
		S.won += maxi(0, g - b)
		gamble_msg = "%s×%d → +%s G" % ["잭팟! " if mult >= 100 else "", mult, Game.fmt(g)]
		gamble_col = Color("ffe27a")
		Res.sfx("win", -2.0)
		if mult >= 40:
			Res.sfx("milestone")
			w.toast("슬롯 ×%d! +%s G" % [mult, Game.fmt(g)], "gold")
	else:
		S.lost += b
		gamble_msg = "꽝… %s G를 잃었어요" % Game.fmt(b)
		gamble_col = Color("ff6b78")
		Res.sfx("miss")
	busy = false
	close_b.disabled = false
	Game.save_game()
	render()

# ---------------- 뽑기 신전 ----------------
func _r_gacha() -> void:
	var S := Game.S
	_lbl("골드를 바쳐 부적을 뽑아요. 확률: N 60% · R 28% · SR 10% · SSR 2%")
	_lbl("%d회 안에 SSR이 꼭 나와요 (지금 %d/%d). 10연차는 R 이상 1장 보장. 같은 부적은 레벨이 올라요(최대 %d)." % [Game.PITY, S.pity, Game.PITY, Game.CHARM_MAX], 14, Color(0.65, 0.7, 0.8))
	var r := _row()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn(r, "1회 뽑기 · %dG" % Game.GACHA_COST, func(): _pull(1), S.gold >= Game.GACHA_COST, Color("8a6a1e"), 17)
	_btn(r, "10회 뽑기 · %dG" % Game.GACHA10, func(): _pull(10), S.gold >= Game.GACHA10, Color("8a6a1e"), 17)
	var info := _lbl("가진 골드 %s G · 총 %d회 뽑음" % [Game.fmt(S.gold), S.pulls], 14)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	_grid = grid
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for o in last_cards:
		grid.add_child(_charm_card(o))

func _charm_card(o: Dictionary) -> Control:
	var c: Dictionary = o.c
	var col := Color(Game.RAR_COL[c.r])
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HUD.box(Color(col, 0.16), 10, col))
	p.custom_minimum_size = Vector2(100, 96)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	for t in [[Game.RAR[c.r], 18, col], [c.n, 13, Color.WHITE], [o.note, 11, Color(0.8, 0.85, 0.9)]]:
		var l := HUD.mk_label(t[0], t[1], t[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	return p

func _pull(n: int) -> void:
	var S := Game.S
	var cost := Game.GACHA10 if n == 10 else Game.GACHA_COST
	if busy or S.gold < cost:
		return
	S.gold -= cost
	var rs := []
	for i in n:
		rs.append(Game.roll_rarity())
	if n == 10 and rs.max() == 0:
		rs[9] = 1
	last_cards = []
	for r in rs:
		last_cards.append(Game.grant(r))
	Game.refresh_stats()
	Game.save_game()
	render()
	busy = true
	_lock_buttons()
	var grid: GridContainer = _grid
	for c in grid.get_children():
		c.modulate.a = 0.0
	await get_tree().process_frame
	var cards := grid.get_children()
	for i in cards.size():
		await get_tree().create_timer(0.17 if i else 0.25).timeout
		var card: Control = cards[i]
		card.pivot_offset = card.size / 2
		card.scale = Vector2(0.6, 0.6)
		var tw := card.create_tween().set_parallel()
		tw.tween_property(card, "modulate:a", 1.0, 0.15)
		tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var r: int = last_cards[i].c.r
		Res.sfx("coin" if r < 2 else "milestone", -4.0, 1.0 + r * 0.15)
	await get_tree().create_timer(0.3).timeout
	busy = false
	close_b.disabled = false
	var best := 0
	for o in last_cards:
		best = maxi(best, o.c.r)
	if best == 3:
		for o in last_cards:
			if o.c.r == 3:
				w.toast("SSR %s 획득!" % o.c.n, "gold")
				break
	render()

# ---------------- 가방 ----------------
func _r_bag() -> void:
	var S := Game.S
	var ST := Game.ST
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	body.add_child(g)
	for t in ["공격력 %d" % ST.dmg, "최대 체력 %d" % ST.max_hp, "받는 피해 -%d%%" % roundi(ST.dr * 100), "채집 힘 %.1f" % ST.power,
			"이동 속도 %d" % roundi(ST.spd), "판정 범위 ×%.2f" % ST.win, "골드 배율 ×%.2f" % ST.gold_mult, "처치 %d · 최고 콤보 %d" % [S.kills, S.best_combo]]:
		_sub(g, t, 15, Color.WHITE)
	var tabs := _row()
	_btn(tabs, "재료", func(): bag_tab = "mats", true, Color("c0392b") if bag_tab == "mats" else Color("2a3350"))
	_btn(tabs, "부적 (%d/3 장착)" % S.equip.size(), func(): bag_tab = "charms", true, Color("c0392b") if bag_tab == "charms" else Color("2a3350"))
	if bag_tab == "mats":
		var have := _have()
		if have.is_empty():
			_lbl("아직 재료가 없어요.")
		for k in have:
			var row := _row()
			_swatch(row, k)
			_sub(row, "%s ×%d · 개당 %dG" % [Game.mat_name(k), Game.mat(k), Game.D.mats[k].p], 15, Color.WHITE)
		_lbl("물약 %d개" % S.potions)
	else:
		_lbl("부적은 3개까지 장착해요. 장착한 부적만 효과가 있어요.", 14)
		var list := Game.CHARMS.duplicate()
		list.sort_custom(func(a, b): return a.r > b.r)
		for c in list:
			var lv := int(S.charms.get(c.id, 0))
			var col := Color(Game.RAR_COL[c.r])
			var eq: bool = c.id in S.equip
			var card := _card(Color(col, 0.1 if lv else 0.03), col if eq else Color(0, 0, 0, 0))
			var row := _row(card)
			if lv == 0:
				_sub(row, "%s  ???  — 뽑기 신전에서 얻을 수 있어요" % Game.RAR[c.r], 14, Color(0.5, 0.55, 0.62))
				continue
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(v)
			_sub(v, "%s  %s  Lv %d" % [Game.RAR[c.r], c.n, lv], 15, col)
			_sub(v, Game.eff_text(c.eff, 1.0 + 0.5 * (lv - 1)), 13)
			_btn(row, "해제" if eq else "장착", func(): _equip(c.id))

func _equip(id: String) -> void:
	var S := Game.S
	var i: int = S.equip.find(id)
	if i >= 0:
		S.equip.remove_at(i)
	else:
		if S.equip.size() >= 3:
			w.toast("부적은 3개까지 장착해요. 하나를 먼저 해제하세요.", "bad")
			return
		S.equip.append(id)
	Game.refresh_stats()
	Res.sfx("coin", -8.0, 1.3)
