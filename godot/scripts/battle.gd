extends CanvasLayer
## 리듬 전투: 몬스터마다 다른 노래에 맞춰 공격(탭·꾹·함정)하고, 공격 신호에 맞춰 방어해요

signal finished(result: String, m)

const HUD := preload("res://scripts/hud.gd")
const MOVES := ["slashDown", "slashUp", "thrust", "spin"]
const APPROACH := 1.7

var w
var m
var type: String
var t: Dictionary
var song: Dictionary
var cmeta: Dictionary
var hmeta: Dictionary
var step_dur: float
var beat: float
var bar_dur: float
var bpb: int
var loop_len: float
var zone := 1

# 시간
var clock := -0.25
var vis := 0.0
var hitstop := 0.0
var intro := 0.0
var music_on := false
var use_audio := true
var loops := 0
var last_pos := 0.0
var stall_t := 0.0
var next_stick := 0
var last_tick := 0
var music: AudioStreamPlayer
var rage: AudioStreamPlayer

# 악보
var notes: Array = []
var sigs: Array = []
var sched: Array = []
var gen_bar := 0
var phase2 := false

# 상태
var hp := 0.0
var hp_lag := 0.0
var p_lag := 0.0
var combo := 0
var max_combo := 0
var milestone_c := 0
var cnt := {"perfect": 0, "good": 0, "miss": 0}
var judg := ""
var judg_t := 0.0
var judg_col := Color.WHITE
var holding = null
var atk_down := false
var move_idx := 0
var p_act = null  # {move, t0, dur}
var p_block := 0.0
var p_hurt := 0.0
var m_hurt := 0.0
var m_knock := 0.0
var stagger := 0.0
var shake := 0.0
var shake_a := 0.0
var zoom := 0.0
var red := 0.0
var flash_w := 0.0
var flash_a := 0.0
var flash_d := 0.0
var over = null  # {win, xp, coins, burst, lines}
var death_t := 0.0
var fx: Array = []
var sp: Array = []
var cf: Array = []
var atm: Array = []
var trail: Array = []
var _slam_q = null
var _venom_q = null

# 노드
var root: Control
var stage: Node2D
var bg: Sprite2D
var under: Node2D
var mon: Sprite2D
var hero: Sprite2D
var over_n: Node2D
var ui: Control
var btn_atk: Button
var btn_def: Button
var btn_pot: Button
var btn_run: Button
var result: PanelContainer
var _glow: Texture2D
var _vign: Texture2D
var _mat: ShaderMaterial
var L := {}

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var black := ColorRect.new()
	black.color = Color("05070c")
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	stage = Node2D.new()
	root.add_child(stage)
	bg = Sprite2D.new()
	bg.centered = false
	stage.add_child(bg)
	under = Node2D.new()
	under.draw.connect(_draw_under)
	stage.add_child(under)
	mon = Sprite2D.new()
	mon.centered = false
	mon.region_enabled = true
	mon.flip_h = true
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/sprite.gdshader")
	mon.material = _mat
	stage.add_child(mon)
	hero = Sprite2D.new()
	hero.centered = false
	hero.region_enabled = true
	stage.add_child(hero)
	over_n = Node2D.new()
	over_n.draw.connect(_draw_over)
	stage.add_child(over_n)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	root.add_child(ui)
	btn_atk = _mk_btn("공격  J", Color("c0392b"), 22)
	btn_atk.button_down.connect(func(): press("atk"))
	btn_atk.button_up.connect(func(): release("atk"))
	btn_def = _mk_btn("방어  K", Color("2a6ab8"), 22)
	btn_def.button_down.connect(func(): press("def"))
	btn_pot = _mk_btn("물약 Q", Color("2a7a4a"), 15)
	btn_pot.pressed.connect(func(): w.use_potion())
	btn_run = _mk_btn("도망 Esc", Color("3a3f50"), 15)
	btn_run.pressed.connect(flee)
	_glow = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 1.0])
	_vign = _radial([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)], [0.0, 0.3, 1.0])
	music = AudioStreamPlayer.new()
	add_child(music)
	rage = AudioStreamPlayer.new()
	add_child(rage)
	get_viewport().size_changed.connect(_layout_buttons)

func _mk_btn(txt: String, col: Color, size: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	HUD.style_button(b, Color(col, 0.85), size)
	root.add_child(b)
	return b

func _radial(cols: Array, offs: Array) -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	g.offsets = PackedFloat32Array(offs)
	var tx := GradientTexture2D.new()
	tx.gradient = g
	tx.fill = GradientTexture2D.FILL_RADIAL
	tx.fill_from = Vector2(0.5, 0.5)
	tx.fill_to = Vector2(1.0, 0.5)
	tx.width = 128
	tx.height = 128
	return tx

# ---------------- 시작 ----------------
func start(monster, world) -> void:
	m = monster
	w = world
	type = m.type
	t = m.t
	song = Game.D.songs[type]
	cmeta = Res.creature_meta[type]
	hmeta = Res.hero_meta.battle
	step_dur = 60.0 / song.bpm / 4.0
	beat = step_dur * 4.0
	bar_dur = step_dur * song.spb
	bpb = int(song.spb) / 4
	loop_len = bar_dur * song.loopBars
	hp = m.hp
	hp_lag = hp
	p_lag = Game.S.hp
	zone = 7 if t.get("boss", false) else maxi(1, Game.zone_at(m.position.x, m.position.y))
	bg.texture = Res.tex("res://assets/bg/battle_%d.png" % zone)
	mon.texture = Res.tex("res://assets/creatures/%s.png" % type)
	hero.texture = Res.tex("res://assets/hero/hero_battle.png")
	var ms: AudioStream = load("res://assets/audio/songs/%s.ogg" % type)
	var rs: AudioStream = load("res://assets/audio/songs/%s_rage.ogg" % type)
	if ms is AudioStreamOggVorbis:
		ms.loop = true
		rs.loop = true
	music.stream = ms
	rage.stream = rs
	music.volume_db = -2.0
	rage.volume_db = -3.0
	use_audio = Game.sound_on
	last_tick = Time.get_ticks_usec()
	_layout_buttons()
	get_tree().create_timer(0.2).timeout.connect(func(): Res.sfx("cry_" + type, -4.0))

func _layout_buttons() -> void:
	var vs := get_viewport().get_visible_rect().size
	L = lay(vs)
	var top: float = L.py + 40.0
	var hgt := maxf(54.0, vs.y - top - 12.0)
	var bw := minf(vs.x * 0.36, 420.0)
	btn_atk.position = Vector2(16, top)
	btn_atk.size = Vector2(bw, hgt)
	btn_def.position = Vector2(vs.x - 16 - bw, top)
	btn_def.size = Vector2(bw, hgt)
	var cw := minf(160.0, vs.x - bw * 2 - 64)
	btn_pot.position = Vector2(vs.x / 2 - cw / 2, top)
	btn_pot.size = Vector2(cw, hgt / 2 - 4)
	btn_run.position = Vector2(vs.x / 2 - cw / 2, top + hgt / 2 + 4)
	btn_run.size = Vector2(cw, hgt / 2 - 4)

func lay(vs: Vector2) -> Dictionary:
	var W := vs.x
	var H := vs.y
	var ly := maxf(H * 0.55, H - 236.0)
	var scene_b := ly - 54.0
	var ground_y := scene_b - maxf(18.0, scene_b * 0.11)
	var sh := ground_y - 40.0
	var boss: bool = t.get("boss", false) if t else false
	var mk := minf(minf(sh * (0.62 if boss else 0.5) / cmeta.height, W * 0.42 / cmeta.width), 4.6) if cmeta else 1.0
	var pk := minf(sh * 0.36 / 52.0, 3.4)
	return {"W": W, "H": H, "ly": ly, "scene_b": scene_b, "ground_y": ground_y, "mk": mk, "pk": pk, "px": W * 0.25, "mx": W * 0.7,
		"py": ly + 25.0 + 14.0}

# ---------------- 박자/악보 ----------------
func bar_start(bar: int) -> float:
	return bar_dur + bar * bar_dur

func chart_bar(bar: int) -> void:
	var src: Array = song.rage if phase2 else song.normal
	var lb: int = song.loopBars
	var idx := bar if bar < 32 else 32 - lb + (bar - 32) % lb
	var b: Dictionary = src[idx]
	var s0 := bar_start(bar)
	for n in b.n:
		var o := {"k": n.k, "t": s0 + n.t, "st": 0}
		if n.k == "hold":
			o.end = s0 + n.e
		notes.append(o)
	for q in b.s:
		sigs.append({"t": s0 + q.t, "lead": q.lead, "heavy": q.heavy, "res": "", "aud": false, "voiced": false})
	notes.sort_custom(func(a, c): return a.t < c.t)
	sigs.sort_custom(func(a, c): return a.t < c.t)

func now_t() -> float:
	return clock + (Time.get_ticks_usec() - last_tick) / 1e6

func win_t() -> Dictionary:
	return {"perf": minf(0.09, 0.06 * Game.ST.win), "good": minf(0.2, 0.13 * Game.ST.win)}

func dwin_t() -> Dictionary:
	return {"perf": minf(0.1, 0.075 * Game.ST.win), "good": minf(0.22, 0.15 * Game.ST.win)}

func _sched(at: float, name: String, vol := 0.0, pitch := 1.0) -> void:
	sched.append({"t": at, "n": name, "v": vol, "p": pitch})

func _update_clock(dt: float) -> void:
	clock += dt
	if use_audio and Game.sound_on:
		if not music_on and clock >= bar_dur:
			music_on = true
			music.play(clock - bar_dur)
		elif music_on and music.playing:
			var pos := music.get_playback_position()
			if pos < last_pos - loop_len * 0.5:
				loops += 1
			if is_equal_approx(pos, last_pos):
				stall_t += dt
				if stall_t > 0.5:
					use_audio = false
			else:
				stall_t = 0.0
			last_pos = pos
			var at := bar_dur + loops * loop_len + pos + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
			if absf(at - clock) > 0.12:
				clock = at
			else:
				clock += (at - clock) * minf(1.0, dt * 4.0)
			if phase2 and rage.playing and absf(rage.get_playback_position() - pos) > 0.06 and absf(rage.get_playback_position() - pos) < loop_len - 0.1:
				rage.seek(pos)
	# 카운트인 막대 소리
	while next_stick < bpb and clock >= next_stick * beat:
		if clock - next_stick * beat < 0.1:
			Res.sfx("sticks_acc" if next_stick == bpb - 1 else "sticks", -2.0)
		next_stick += 1

# ---------------- 연출 도우미 ----------------
func set_judg(txt: String, col: Color) -> void:
	judg = txt
	judg_col = col
	judg_t = 0.6

func c_float(txt: String, col: Color, p: Vector2, size := 22) -> void:
	cf.append({"txt": txt, "col": col, "p": p, "size": size, "t": 0.0, "vx": randf_range(-24, 24)})

func sparks(p: Vector2, n: int, cols: Array, spd := 260.0, o := {}) -> void:
	for i in n:
		var a: float = o.dir + randf_range(-o.spread, o.spread) if o.has("dir") else randf() * TAU
		var v := randf_range(spd * 0.35, spd)
		sp.append({"p": p, "v": Vector2(cos(a), sin(a)) * v, "t": -o.get("d", 0.0), "life": randf_range(0.3, 0.65) * o.get("life", 1.0),
			"col": Color(cols.pick_random()), "s": randf_range(1.5, 3.5) * o.get("big", 1.0), "g": o.get("g", 520.0), "k": o.get("k", "line")})

func add_fx(o: Dictionary) -> void:
	o.t = 0.0
	if not o.has("d"):
		o.d = 0.0
	fx.append(o)

func mon_center() -> Vector2:
	var fly: float = Res.FLY.get(type, 0.0) * L.mk * 0.6
	return Vector2(L.mx - m_pose().dash, L.ground_y - cmeta.height * L.mk * 0.5 - fly)

func hero_pos() -> Vector2:
	return Vector2(L.px, L.ground_y - 26.0 * L.pk)

func act(move: String, dur := 0.32) -> void:
	p_act = {"move": move, "t0": vis, "dur": dur}
	trail.clear()

func enrage() -> void:
	phase2 = true
	shake = maxf(shake, 0.35)
	red = 0.25
	add_fx({"k": "banner", "txt": "분노! 2페이즈", "life": 1.4})
	get_tree().create_timer(0.12).timeout.connect(func():
		if over == null:
			Res.sfx("cry_" + type, -4.0))
	if music_on and use_audio and Game.sound_on:
		rage.play(music.get_playback_position())

func hit_monster(dmg: float, perf: bool, opts := {}) -> void:
	var d := roundi(dmg)
	hp -= d
	m_hurt = 0.3
	m_knock = opts.get("knock", 1.0)
	if not phase2 and hp > 0 and hp < t.hp * 0.5:
		enrage()
	var c := mon_center()
	var mat: String = Res.MAT.get(type, "fur")
	var mc: Array = Res.MAT_COL[mat].map(func(h): return "#" + h)
	hitstop = maxf(hitstop, opts.get("stop", 0.085 if perf else 0.05))
	shake = maxf(shake, opts.get("shake", 0.17 if perf else 0.09))
	shake_a = randf_range(-0.6, 0.6)
	if perf:
		zoom = maxf(zoom, 0.045)
	var r := maxf(36.0, cmeta.height * L.mk * 0.45)
	var ang: float = opts.get("ang", randf_range(-0.6, 0.6))
	add_fx({"k": "slash", "p": c, "r": r, "a": ang - 2.4, "b": ang + 0.6, "life": 0.22, "col": Color(1, 0.894, 0.55) if perf else Color.WHITE, "w": 10.0 if perf else 7.0, "d": 0.03})
	if perf:
		add_fx({"k": "ring", "p": c, "r0": 10.0, "r1": r * 1.5, "life": 0.3, "col": Color(1, 0.894, 0.55), "w": 4.0, "d": 0.03})
		add_fx({"k": "lines", "p": c, "life": 0.16, "d": 0.03})
	if opts.get("cross", false):
		add_fx({"k": "slash", "p": c, "r": r * 1.1, "a": ang + 1.4, "b": ang + 4.2, "life": 0.26, "col": Color(1, 0.94, 0.75), "w": 11.0, "d": 0.1})
	sparks(c, 22 if perf else 12, ["#fff6c8", "#ffd35a", "#ffffff"] if perf else ["#ffffff", "#cfe8ff"], 420.0 if perf else 300.0, {"dir": -0.25, "spread": 1.3, "d": 0.03})
	sparks(c, 14 if perf else 8, mc, 200.0, {"k": "dot", "g": 380.0, "d": 0.03, "big": 1.1})
	c_float(("* " if perf else "") + str(d), Color("ffe27a") if perf else Color.WHITE, c + Vector2(randf_range(-30, 30), -34), 36 if perf else 28)
	Res.sfx("hit_%s_%d" % [mat, 1 if perf else 0], -1.0, randf_range(0.95, 1.05))
	check_end()

func atk_hit(n: Dictionary, perf: bool, kind: String) -> void:
	combo += 1
	max_combo = maxi(max_combo, combo)
	cnt["perfect" if perf else "good"] += 1
	set_judg("PERFECT!" if perf else "GOOD", Color("ffe27a") if perf else Color("8ee6ff"))
	var mult := (1.5 if perf else 1.0) * (1.0 + mini(combo, 40) * 0.025)
	if kind == "tap":
		var mv: String = MOVES[move_idx % 4]
		move_idx += 1
		act(mv)
		var ang := 2.6 if mv == "slashUp" else 1.6 if mv == "thrust" else 0.0 if mv == "spin" else -0.4
		hit_monster(Game.ST.dmg * mult, perf, {"ang": ang})
	else:
		act("flurry", 99.0)
		hit_monster(Game.ST.dmg * mult * 0.6, perf)
	if perf and Game.ST.steal > 0:
		Game.S.hp = minf(Game.max_hp(), Game.S.hp + Game.ST.steal)
	milestone()

func milestone() -> void:
	if combo >= 10 and combo % 10 == 0 and combo > milestone_c:
		milestone_c = combo
		add_fx({"k": "banner", "txt": "%d COMBO!" % combo, "life": 0.9})
		Res.sfx("milestone", -4.0)

func break_combo() -> void:
	combo = 0
	milestone_c = 0

func end_hold(h: Dictionary, at: float) -> void:
	if holding != h:
		return
	holding = null
	h.st = 2
	if at >= h.end - win_t().good - 0.05:
		combo += 1
		max_combo = maxi(max_combo, combo)
		cnt.perfect += 1
		set_judg("FINISH!", Color("ffcf4a"))
		act("finisher", 0.5)
		hit_monster(Game.ST.dmg * 2.2 * (1.0 + mini(combo, 40) * 0.025), true, {"cross": true, "stop": 0.12, "shake": 0.3, "knock": 1.6})
		flash_w = 0.18
		milestone()
	else:
		set_judg("끊김", Color("9aa6b8"))
		break_combo()
		cnt.miss += 1
		p_act = null
		Res.sfx("miss")

func trap_hit(n: Dictionary) -> void:
	n.st = 2
	var hp0 := hero_pos()
	var d := maxi(2, roundi(t.atk * 0.6 * (1.0 - Game.ST.dr)))
	Game.S.hp -= d
	break_combo()
	cnt.miss += 1
	p_hurt = 0.45
	red = 0.4
	shake = 0.3
	act("stumble", 0.4)
	set_judg("함정!", Color("c58bff"))
	add_fx({"k": "ring", "p": hp0 + Vector2(20, 0), "r0": 6.0, "r1": 70.0, "life": 0.35, "col": Color(0.75, 0.47, 1), "w": 5.0})
	sparks(hp0 + Vector2(20, 0), 22, ["#c58bff", "#7a3cae", "#ffffff"], 300.0, {"k": "dot"})
	c_float("-%d" % d, Color("d9a8ff"), hp0 + Vector2(0, -50), 28)
	Res.sfx("trap")
	check_end()

func whiff() -> void:
	if p_act == null or vis - p_act.t0 > p_act.dur * 0.6:
		act("whiff", 0.26)
		Res.sfx("whiff", -6.0)

func block_sig(q: Dictionary, perf: bool, at: float) -> void:
	q.res = "parry" if perf else "block"
	q.res_t = maxf(at, q.t - 0.05)
	var hp0 := hero_pos()
	var c := Vector2(hp0.x + 26 * L.pk, hp0.y - 4 * L.pk)
	combo += 1
	max_combo = maxi(max_combo, combo)
	cnt["perfect" if perf else "good"] += 1
	p_block = 0.35
	var d := maxf(0.0, q.t - at + 0.02)
	sparks(c, 26 if perf else 14, ["#fff7d1", "#ffd35a", "#ffae3a"], 340.0, {"d": d, "dir": 0.0, "spread": 1.6})
	add_fx({"k": "ring", "p": c, "r0": 6.0, "r1": 70.0 if perf else 46.0, "life": 0.26, "col": Color(1, 0.9, 0.63), "w": 4.0, "d": d})
	get_tree().create_timer(d).timeout.connect(func(): Res.sfx("parry" if perf else "block"))
	if perf:
		set_judg("BREAK!" if q.heavy else "PARRY!", Color("ffe27a"))
		stagger = 1.3 if q.heavy else 0.5
		get_tree().create_timer(d + 0.06).timeout.connect(func():
			if over != null:
				return
			act("riposte", 0.3)
			hit_monster(Game.ST.dmg * (1.8 if q.heavy else 0.7), true, {"ang": -0.2, "shake": 0.3 if q.heavy else 0.12}))
	elif q.heavy:
		var dm := maxi(1, roundi(t.atk * 0.35 * (1.0 - Game.ST.dr)))
		Game.S.hp -= dm
		set_judg("GUARD", Color("8ee6ff"))
		c_float("-%d" % dm, Color("ff9aa4"), hp0 + Vector2(0, -50), 22)
		check_end()
	else:
		set_judg("GUARD", Color("8ee6ff"))
	milestone()

func sig_hit(q: Dictionary) -> void:
	q.res = "hit"
	q.res_t = clock
	var hp0 := hero_pos()
	var d := maxi(1, roundi(t.atk * (1.8 if q.heavy else 1.0) * (1.25 if phase2 else 1.0) * (1.0 - Game.ST.dr)))
	Game.S.hp -= d
	red = 0.55 if q.heavy else 0.4
	shake = 0.4 if q.heavy else 0.28
	p_hurt = 0.45
	break_combo()
	cnt.miss += 1
	act("hurt", 0.4)
	set_judg("맞았다!", Color("ff7a7a"))
	sparks(hp0 + Vector2(6, 0), 16, ["#ff5d6c", "#ff9aa4", "#ffffff"], 280.0, {"dir": PI + 0.2, "spread": 1.1})
	c_float("-%d" % d, Color("ff6b78"), hp0 + Vector2(0, -50 * L.pk / 2.0), 34 if q.heavy else 28)
	Res.sfx("hurt")
	check_end()

# ---------------- 입력 ----------------
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.echo:
		get_viewport().set_input_as_handled()
		return
	if over != null:
		if result and result.visible and e.is_action_pressed("confirm"):
			close_result()
			get_viewport().set_input_as_handled()
		return
	var used := true
	if e.is_action_pressed("attack"):
		press("atk")
	elif e.is_action_released("attack"):
		release("atk")
	elif e.is_action_pressed("defend"):
		press("def")
	elif e.is_action_pressed("potion"):
		w.use_potion()
	elif e.is_action_pressed("flee"):
		flee()
	else:
		used = false
	if used:
		get_viewport().set_input_as_handled()

func press(kind: String) -> void:
	if over != null or intro < 0.4:
		return
	var at := now_t()
	if kind == "atk":
		if atk_down:
			return
		atk_down = true
		flash_a = 0.12
		var wn := win_t()
		var best = null
		var bd := 1e9
		for n in notes:
			if n.st != 0:
				continue
			var d: float = absf(n.t - at)
			if d < bd:
				bd = d
				best = n
			if n.t - at > 0.4:
				break
		if best and best.k == "trap" and bd <= 0.11:
			trap_hit(best)
		elif best and best.k != "trap" and bd <= wn.good:
			var perf: bool = bd <= wn.perf
			best.hit = true
			best.ht = 0.0
			if best.k == "tap":
				best.st = 2
				atk_hit(best, perf, "tap")
			else:
				best.st = 1
				best.next = best.t + beat / 2.0
				holding = best
				atk_hit(best, perf, "hold")
		elif best and best.k != "trap" and best.t > at and best.t - at < 0.3:
			set_judg("너무 빨라요", Color("ffb36b"))
			break_combo()
			whiff()
		else:
			whiff()
	else:
		flash_d = 0.12
		var dw := dwin_t()
		var best = null
		var bd := 1e9
		for q in sigs:
			if q.res != "":
				continue
			var d: float = absf(q.t - at)
			if d < bd:
				bd = d
				best = q
		if best and bd <= dw.good:
			block_sig(best, bd <= dw.perf, at)
		elif best and best.t > at and best.t - at < 0.4:
			best.res = "early"
			set_judg("너무 빨라요", Color("ffb36b"))
			p_block = 0.3
		else:
			p_block = 0.3

func release(kind: String) -> void:
	if kind == "atk":
		atk_down = false
		if holding and over == null:
			end_hold(holding, now_t())

func on_potion(h: int) -> void:
	var hp0 := hero_pos()
	c_float("+%d" % h, Color("5fdc8a"), hp0 + Vector2(0, -50), 26)
	sparks(hp0 + Vector2(0, 10), 16, ["#8dffb0", "#d6ffe2"], 120.0, {"g": -120.0, "k": "dot"})

func check_end() -> void:
	if over != null:
		return
	if hp <= 0:
		finish(true)
	elif Game.S.hp <= 0:
		finish(false)

func finish(won: bool) -> void:
	var S := Game.S
	S.best_combo = maxi(S.best_combo, max_combo)
	holding = null
	var lines: Array = []
	if won:
		var bonus := mini(50, max_combo)
		var g := roundi(randi_range(t.gold[0], t.gold[1]) * Game.ST.gold_mult * (1.0 + bonus / 100.0))
		S.gold += g
		lines.append(["+%s 골드  (콤보 보너스 +%d%%)" % [Game.fmt(g), bonus], Color("ffd24a")])
		var dbl: bool = randf() < Game.ST.dbl
		for dr in t.drop:
			if randf() > dr[3]:
				continue
			var amt: int = randi_range(dr[1], dr[2]) * (2 if dbl else 1)
			if amt <= 0:
				continue
			Game.add_mat(dr[0], amt)
			lines.append(["%s +%d%s" % [Game.mat_name(dr[0]), amt, " (두 배!)" if dbl else ""], Color.WHITE])
		lines.append(["경험치 +%d" % t.xp, Color("8ee6ff")])
		lines.append(["퍼펙트 %d · 굿 %d · 미스 %d · 최대 콤보 %d" % [cnt.perfect, cnt.good, cnt.miss, max_combo], Color(0.6, 0.65, 0.75)])
		S.kills += 1
		if t.get("boss", false):
			w.toast("고대 용을 쓰러뜨렸어요! 4분 뒤 다시 깨어나요", "gold")
		over = {"win": true, "xp": t.xp, "coins": mini(26, 6 + g / 15), "burst": false, "lines": lines}
		hitstop = 0.3
		flash_w = 0.25
		zoom = 0.08
		get_tree().create_timer(0.25).timeout.connect(func(): Res.sfx("cry_" + type, -4.0))
		get_tree().create_timer(1.3).timeout.connect(func(): Res.sfx("win"))
	else:
		var lost := int(S.gold * 0.25)
		S.gold -= lost
		m.hp = t.hp
		S.hp = 0
		lines.append(["골드 %s을(를) 잃었어요" % Game.fmt(lost), Color("ff6b78")])
		lines.append(["마을에서 깨어나요. 대장간에서 장비를 강화해 보세요.", Color(0.8, 0.85, 0.9)])
		Res.sfx("lose")
		get_tree().create_timer(0.4).timeout.connect(func(): Res.sfx("cry_" + type, -4.0))
		over = {"win": false, "lines": lines}
	var tw := create_tween()
	tw.tween_property(music, "volume_db", -40.0, 1.6)
	tw.parallel().tween_property(rage, "volume_db", -40.0, 1.6)
	death_t = 0.0
	for b in [btn_atk, btn_def, btn_pot, btn_run]:
		b.visible = false
	get_tree().create_timer(2.1).timeout.connect(_show_result)

func _show_result() -> void:
	result = PanelContainer.new()
	result.add_theme_stylebox_override("panel", HUD.box(Color(0.06, 0.07, 0.12, 0.96), 18, Color("ffcf4a") if over.win else Color("ff6b78")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	result.add_child(v)
	var ttl := HUD.mk_label("승리!" if over.win else "쓰러졌어요", 34, Color("ffcf4a") if over.win else Color("ff6b78"))
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ttl)
	for ln in over.lines:
		var l := HUD.mk_label(ln[0], 17, ln[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var b := Button.new()
	b.text = "확인 (Enter)"
	b.focus_mode = Control.FOCUS_NONE
	HUD.style_button(b, Color("c0392b"), 18)
	b.custom_minimum_size = Vector2(220, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(close_result)
	v.add_child(b)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	cc.add_child(result)
	result.modulate.a = 0.0
	await get_tree().process_frame
	result.pivot_offset = result.size / 2
	result.scale = Vector2(0.85, 0.85)
	result.modulate.a = 0.0
	var tw := result.create_tween().set_parallel()
	tw.tween_property(result, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(result, "modulate:a", 1.0, 0.2)

func close_result() -> void:
	if over == null or result == null:
		return
	music.stop()
	rage.stop()
	if over.win:
		var ups := Game.add_xp(over.xp)
		if ups > 0:
			w.on_level_up(ups)
		finished.emit("win", m)
	else:
		finished.emit("lose", m)

func flee() -> void:
	if over != null:
		return
	m.hp = maxf(1.0, hp)
	music.stop()
	rage.stop()
	over = {"win": false, "fled": true, "lines": []}
	finished.emit("flee", m)

# ---------------- 매 프레임 ----------------
func _process(dt: float) -> void:
	last_tick = Time.get_ticks_usec()
	var vs := get_viewport().get_visible_rect().size
	L = lay(vs)
	intro = minf(1.0, intro + dt / 0.8)
	if hitstop > 0:
		hitstop = maxf(0.0, hitstop - dt)
	else:
		vis += dt
	m_hurt = maxf(0.0, m_hurt - dt)
	m_knock = maxf(0.0, m_knock - dt * 4.5)
	stagger = maxf(0.0, stagger - dt)
	p_block = maxf(0.0, p_block - dt)
	p_hurt = maxf(0.0, p_hurt - dt)
	flash_w = maxf(0.0, flash_w - dt)
	flash_a = maxf(0.0, flash_a - dt)
	flash_d = maxf(0.0, flash_d - dt)
	zoom = maxf(0.0, zoom - dt * 0.35)
	red = maxf(0.0, red - dt)
	shake = maxf(0.0, shake - dt)
	hp_lag += (hp - hp_lag) * minf(1.0, dt * (2.5 if hp_lag > hp else 20.0))
	p_lag += (Game.S.hp - p_lag) * minf(1.0, dt * (2.5 if p_lag > Game.S.hp else 20.0))
	judg_t = maxf(0.0, judg_t - dt)
	for f in cf:
		f.t += dt
	cf = cf.filter(func(f): return f.t < 1.0)
	for f in fx:
		f.t += dt
	fx = fx.filter(func(f): return f.t - f.d < f.life)
	for p in sp:
		p.t += dt
		if p.t < 0:
			continue
		if p.k == "coin":
			var k := minf(1.0, p.t / p.life)
			var e := k * k
			p.p = p.p0 + (p.tp - p.p0) * e + Vector2(sin(k * PI) * p.bx, -sin(k * PI) * p.by)
			if k >= 1 and not p.done:
				p.done = true
				Res.sfx("coin", -14.0, randf_range(1.2, 1.5))
			continue
		p.p += p.v * dt
		p.v.y += p.g * dt
		p.v.x *= (1.0 - dt * 2.0)
	sp = sp.filter(func(p): return p.t < p.life)
	_update_atm(dt)
	if over != null:
		death_t += dt
		if over.win and not over.burst and death_t > 1.05:
			over.burst = true
			var c := mon_center()
			var mc: Array = Res.MAT_COL[Res.MAT.get(type, "fur")].map(func(h): return "#" + h)
			sparks(c, 34, mc + ["#ffffff", "#fff3b0"], 160.0, {"g": -90.0, "k": "dot", "big": 1.3, "life": 1.8})
			add_fx({"k": "ring", "p": c + Vector2(0, 10), "r0": 10.0, "r1": 110.0, "life": 0.5, "col": Color.WHITE, "w": 3.0})
			var gp: Vector2 = w.hud.gold_pos()
			for i in over.coins:
				sp.append({"k": "coin", "p0": c + Vector2(randf_range(-20, 20), randf_range(-20, 20)), "p": c, "tp": gp, "bx": randf_range(-80, 80), "by": randf_range(40, 140),
					"t": -i * 0.04 - 0.1, "life": randf_range(0.7, 0.95), "col": Color("ffd24a"), "s": 5.0, "g": 0.0, "done": false, "v": Vector2.ZERO})
		_render()
		return
	_update_clock(dt)
	while bar_start(gen_bar) < clock + APPROACH + 2.5 * beat:
		chart_bar(gen_bar)
		gen_bar += 1
	_audio_sched()
	var wn := win_t()
	var dw := dwin_t()
	for n in notes:
		if n.st != 0:
			continue
		if n.k == "trap":
			if clock - n.t > 0.11:
				n.st = 2
				n.dodged = true
			continue
		if clock - n.t > wn.good:
			n.st = 2
			n.missed = true
			cnt.miss += 1
			break_combo()
			set_judg("MISS", Color("9aa6b8"))
	var h = holding
	if h:
		while h.next <= clock and h.next < h.end - 0.05:
			h.next += beat / 2.0
			hit_monster(Game.ST.dmg * 0.35 * (1.0 + mini(combo, 40) * 0.02), false, {"stop": 0.02, "shake": 0.05, "ang": randf_range(-2, 2)})
			if over != null:
				_render()
				return
		if clock >= h.end + 0.04:
			end_hold(h, h.end)
	for n in notes:
		if n.get("hit", false):
			n.ht = n.get("ht", 0.0) + dt
	notes = notes.filter(func(n): return n.st != 2 or (n.get("hit", false) and n.ht < 0.3) or (clock - n.get("end", n.t) < 0.4))
	for q in sigs:
		if not q.voiced and clock >= q.t - 0.06:
			q.voiced = true
			Res.sfx("atk_" + type, -3.0)
		if q.res == "" or q.res == "early":
			if clock - q.t > dw.good:
				sig_hit(q)
				if over != null:
					_render()
					return
	sigs = sigs.filter(func(q): return clock - q.t < 1.2)
	_special_fx()
	_render()

func _audio_sched() -> void:
	for q in sigs:
		if q.aud or q.t - q.lead - 0.05 > clock + 0.05:
			continue
		q.aud = true
		var nb := roundi(q.lead / beat)
		for i in range(nb, 0, -1):
			var tt: float = q.t - i * beat
			if tt > clock - 0.02:
				_sched(tt, "chime_" + type, 0.0 if i == 1 else -5.0, 1.0 if i == 1 else 0.75)
		_sched(q.t, ("stabh_" if q.heavy else "stab_") + type, 0.0)
	var keep := []
	for s in sched:
		if clock >= s.t - 0.01:
			if clock - s.t < 0.15:
				Res.sfx(s.n, s.v, s.p)
		else:
			keep.append(s)
	sched = keep

func _special_fx() -> void:
	var mp := m_pose()
	var mx: float = L.mx - mp.dash
	var k: float = L.mk
	if type == "dragon" and mp.lunge > 0.3:
		var mo := Vector2(mx - cmeta.width * k * 0.42, L.ground_y - cmeta.height * k * 0.62)
		for i in 4:
			sp.append({"p": mo, "v": Vector2(-randf_range(420, 700), randf_range(-50, 110)), "t": 0.0, "life": randf_range(0.35, 0.6),
				"col": Color(["#fff3a0", "#ffb43a", "#ff6a1f", "#e03a12"].pick_random()), "s": randf_range(6, 13), "g": -60.0, "k": "fire"})
	if mp.lunge > 0.85 and type in ["golem", "yeti", "worm"] and _slam_q != mp.q:
		_slam_q = mp.q
		shake = maxf(shake, 0.22)
		var gx: float = mx - 22.0 * k
		add_fx({"k": "ring", "p": Vector2(gx, L.ground_y), "r0": 10.0, "r1": 150.0, "life": 0.45, "col": Color(0.82, 0.78, 0.7), "w": 5.0, "flat": true})
		sparks(Vector2(gx, L.ground_y - 4), 16, ["#ffffff", "#cfe8ff"] if type == "yeti" else ["#9a9284", "#c9c1b0", "#d8b67a"], 240.0, {"dir": -PI / 2, "spread": 1.2, "k": "dot"})
	if type == "wisp" and mp.lunge > 0.2 and randf() < 0.5:
		var c := mon_center()
		sp.append({"p": c, "v": Vector2(-randf_range(500, 800), randf_range(-60, 60)), "t": 0.0, "life": 0.45, "col": Color("dff6ff"), "s": 3.0, "g": 0.0, "k": "shard"})
	if type == "scorp" and mp.lunge > 0.8 and _venom_q != mp.q:
		_venom_q = mp.q
		sparks(hero_pos() + Vector2(20, -10), 10, ["#b8ff60", "#6fdc2a"], 200.0, {"k": "dot", "g": 300.0})

func _update_atm(dt: float) -> void:
	var W: float = L.W
	var gy: float = L.ground_y
	if atm.size() < 46 and randf() < dt * 16:
		var a := {}
		match zone:
			7: a = {"p": Vector2(randf() * W, L.scene_b), "v": Vector2(randf_range(-10, 10), randf_range(-60, -30)), "r": randf_range(1, 2.4), "col": Color(1, 0.55, 0.2), "glow": true}
			4: a = {"p": Vector2(randf_range(-40, W), randf_range(-20, gy)), "v": Vector2(randf_range(10, 30), randf_range(25, 45)), "r": randf_range(1, 2.6), "col": Color.WHITE}
			5: a = {"p": Vector2(randf() * W, randf_range(gy * 0.5, gy)), "v": Vector2(randf_range(30, 60), randf_range(-4, 4)), "r": randf_range(0.8, 1.6), "col": Color(0.9, 0.78, 0.59)}
			6: a = {"p": Vector2(randf() * W, randf_range(60, gy)), "v": Vector2(randf_range(-6, 6), randf_range(-6, 6)), "r": 1.8, "col": Color(0.78, 1, 0.55), "glow": true}
			3: a = {"p": Vector2(randf() * W, randf_range(40, gy)), "v": Vector2(randf_range(5, 18), randf_range(-4, 4)), "r": randf_range(1, 2), "col": Color(0.9, 0.82, 0.67)}
			2: a = {"p": Vector2(randf() * W, randf_range(60, gy)), "v": Vector2(randf_range(-8, 8), randf_range(-8, 8)), "r": 1.8, "col": Color(0.86, 1, 0.55), "glow": true}
			_: a = {"p": Vector2(randf() * W, randf_range(40, gy)), "v": Vector2(randf_range(6, 20), randf_range(-6, 6)), "r": randf_range(1, 1.8), "col": Color(1, 0.98, 0.82)}
		a.t = 0.0
		a.life = randf_range(2, 4.5)
		atm.append(a)
	for a in atm:
		a.t += dt
		a.p += a.v * dt
	atm = atm.filter(func(a): return a.t < a.life)

# 몬스터 자세: 방어 신호가 시작되면 웅크렸다가(wind) 신호가 끝나는 순간 덮쳐요(lunge)
func m_pose() -> Dictionary:
	var wind := 0.0
	var lunge := 0.0
	var q0 = null
	if over != null:
		return {"wind": 0.0, "lunge": 0.0, "dash": 0.0, "q": null, "heavy": false}
	for q in sigs:
		var s: float = q.t - q.lead
		if clock < s or clock > q.t + 0.6:
			continue
		if clock < q.t - 0.1:
			var p: float = (clock - s) / maxf(0.05, q.lead - 0.1)
			if p > wind:
				wind = smoothstep(0.0, 1.0, clampf(p, 0, 1))
				if q0 == null:
					q0 = q
		else:
			var end_t: float = maxf(q.get("res_t", q.t), q.t) if (q.res != "" and q.res != "early") else q.t + dwin_t().good
			var v := 0.0
			if clock < q.t:
				v = (clock - (q.t - 0.1)) / 0.1
			elif clock < end_t:
				v = 1.0
			else:
				v = 1.0 - (clock - end_t) / 0.3
			v = clampf(v, 0, 1)
			if v > lunge:
				lunge = v
				q0 = q
	if stagger > 0:
		wind = 0.0
		lunge *= 0.3
	var ranged := type in ["dragon", "wisp", "toad"]
	var reach := maxf(0.0, L.mx - L.px - (cmeta.width * L.mk * 0.32 + 24.0 * L.pk))
	var blocked: bool = q0 != null and (q0.res == "block" or q0.res == "parry")
	var el := smoothstep(0.0, 1.0, lunge)
	return {"wind": wind * (1.0 - lunge), "lunge": el, "dash": el * reach * (0.15 if ranged else 0.85 if blocked else 1.0), "q": q0, "heavy": q0 != null and q0.heavy}

# ---------------- 그리기 ----------------
var _mx := 0.0
var _hx := 0.0
var _hy := 0.0
var _fly := 0.0
var _pulse := 0.0
var _phase := 0.0
var _ein := 0.0
var _mp := {}

func _hero_frame() -> Dictionary:
	var st: Dictionary = hmeta.states
	var name := "idle"
	var i := 0
	if over != null and not over.win:
		name = "dead"
		i = clampi(int(clampf(death_t / 0.7, 0, 1) * 9.0 + 0.5), 0, 9)
	elif p_act != null:
		var mv: String = p_act.move
		if mv == "flurry":
			if holding == null:
				p_act = null
			else:
				name = "flurry"
				i = int(fposmod(vis, TAU / 30.0) / (TAU / 30.0) * 8.0) % 8
		else:
			var p: float = (vis - p_act.t0) / p_act.dur
			if p >= 1.0:
				p_act = null
			else:
				name = mv
				i = clampi(int(p * st[mv].count), 0, int(st[mv].count) - 1)
	if p_act == null and name == "idle":
		if p_block > 0:
			name = "block"
		else:
			i = int(_phase * 8.0) % 8 if clock >= 0 else int(fposmod(vis, 0.5) / 0.5 * 8.0) % 8
	var s: Dictionary = st[name]
	var f: Dictionary = s.frames[i]
	return {"idx": int(s.start) + i, "f": f}

func _render() -> void:
	var W: float = L.W
	var gy: float = L.ground_y
	_phase = fposmod(clock, beat) / beat
	_pulse = maxf(0.0, 1.0 - _phase * 3.5) if clock >= 0 and over == null else 0.0
	_ein = 1.0 - pow(1.0 - intro, 3.0)
	# 흔들림과 확대
	var sh := Vector2.ZERO
	if shake > 0:
		sh = Vector2(cos(shake_a) * randf_range(-1, 1) * 8.0 * shake * 3.5, randf_range(-5, 5) * shake * 3.5)
	var zm := 1.0 + zoom + _pulse * 0.004
	stage.transform = Transform2D(0, Vector2(zm, zm), 0, Vector2(W * 0.5, gy) + sh) * Transform2D(0, -Vector2(W * 0.5, gy))
	# 배경: 땅 높이를 맞춰서
	var s := maxf(maxf(W / 1600.0, gy / 548.0), (L.scene_b - gy) / 92.0)
	bg.scale = Vector2(s, s)
	bg.position = Vector2((W - 1600.0 * s) / 2.0, gy - 548.0 * s)
	# 몬스터
	_mp = m_pose()
	var won: bool = over != null and over.win
	var dead_k := clampf((death_t - 0.35) / 0.6, 0, 1) if won else 0.0
	var mk: float = L.mk
	_fly = (Res.FLY.get(type, 0.0) * mk * 0.6 * (1.0 - dead_k) + sin(vis * 3.0) * 4.0 * (1.0 - dead_k)) if Res.FLY.has(type) else 0.0
	var stag := sin(vis * 40.0) * 3.0 * minf(1.0, stagger) if stagger > 0 else 0.0
	_mx = L.mx + (1.0 - _ein) * W * 0.45 + m_knock * 26.0 - _mp.dash + stag
	var idx := 0
	var stt: Dictionary = cmeta.states
	if won:
		idx = int(stt.dead.start) + clampi(int(dead_k * 9.0 + 0.5), 0, 9)
	elif type == "worm" and intro < 0.77:
		idx = int(stt.emerge.start) + clampi(int(intro * 1.3 * 6.0), 0, 5)
	elif _ein < 0.95:
		idx = int(stt.walk.start) + int(vis * 10.0) % 8
	elif _mp.lunge > 0.05:
		var l: float = _mp.lunge
		idx = int(stt.lunge.start) + (0 if l < 0.47 else 1 if l < 0.77 else 2 if l < 0.95 else 3)
	elif _mp.wind > 0.05:
		idx = int(stt.wind.start) + clampi(roundi(_mp.wind * 5.0) - 1, 0, 4)
	elif m_hurt > 0.05:
		idx = int(stt.hurt.start) + (0 if m_hurt < 0.15 else 1)
	else:
		idx = int(stt.ready.start) + int(fposmod(vis, 3.0) / 3.0 * 8.0) % 8
	mon.region_rect = Res.cell(cmeta, idx)
	mon.offset = -Vector2(cmeta.ox, cmeta.oy)
	mon.scale = Vector2(mk / cmeta.ps, mk / cmeta.ps)
	mon.position = Vector2(_mx, gy - _fly)
	var flash := minf(1.0, m_hurt / 0.3) * 0.85
	if won and death_t < 0.4:
		flash = 0.9 if sin(death_t * 45.0) > 0 else 0.2
	_mat.set_shader_parameter("flash", flash)
	var danger := (1.0 if _mp.heavy else 0.55) * (0.6 + 0.4 * sin(vis * 20.0)) if _mp.wind > 0 and over == null else 0.0
	if danger > 0:
		_mat.set_shader_parameter("rim_color", Color(1, 0.16 if _mp.heavy else 0.47, 0.16, 0.6 + danger * 0.4))
		_mat.set_shader_parameter("rim_px", (2.5 + danger * 1.5) / mk * cmeta.ps)
	elif phase2:
		_mat.set_shader_parameter("rim_color", Color(0.86, 0.16, 0.12, 0.55 + 0.25 * sin(vis * 6.0)))
		_mat.set_shader_parameter("rim_px", 2.0 / mk * cmeta.ps)
	else:
		_mat.set_shader_parameter("rim_color", Color(0.06, 0.05, 0.04, 0.5))
		_mat.set_shader_parameter("rim_px", 1.2 / mk * cmeta.ps)
	mon.modulate.a = maxf(0.0, 1.0 - (death_t - 1.05) / 0.6) if won and death_t > 1.05 else 1.0
	# 사냥꾼
	var hf := _hero_frame()
	var f: Dictionary = hf.f
	var pk: float = L.pk
	var reach_p := maxf(0.0, (_mx - L.px) - (cmeta.width * mk * 0.3 + 30.0 * pk))
	_hx = L.px - (1.0 - _ein) * W * 0.4 + f.dx * reach_p - p_hurt * 16.0 * pk / 2.0
	_hy = gy + f.dy * pk / 2.0
	hero.region_rect = Res.cell(hmeta, hf.idx)
	hero.offset = -Vector2(hmeta.ox, hmeta.oy)
	hero.scale = Vector2(pk / hmeta.ps, pk / hmeta.ps)
	hero.position = Vector2(_hx, _hy - _pulse * 1.2 * pk)
	hero.modulate.a = 0.45 if p_hurt > 0 and int(p_hurt * 24.0) % 2 == 1 else 1.0
	if f.strike or (p_act != null and p_act.move == "flurry"):
		trail.append({"p": Vector2(_hx + f.tip[0] * pk, _hy + f.tip[1] * pk), "t": vis})
	trail = trail.filter(func(q): return vis - q.t < 0.1)
	under.queue_redraw()
	over_n.queue_redraw()
	ui.queue_redraw()

func _glow_at(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	c.draw_texture_rect(_glow, Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), false, col)

func _ellipse(c: CanvasItem, p: Vector2, rx: float, ry: float, col: Color) -> void:
	c.draw_set_transform(p, 0, Vector2(1, ry / maxf(rx, 0.01)))
	c.draw_circle(Vector2.ZERO, rx, col)
	c.draw_set_transform(Vector2.ZERO)

func label(c: CanvasItem, txt: String, p: Vector2, col: Color, size: float) -> void:
	var fs := int(size)
	var pos := Vector2(p.x - 400, p.y + fs * 0.36)
	c.draw_string_outline(Res.font_xbold, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 800, fs, maxi(3, fs / 5), Color(0, 0, 0, 0.7 * col.a))
	c.draw_string(Res.font_xbold, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 800, fs, col)

func _draw_under() -> void:
	var c := under
	var gy: float = L.ground_y
	for a in atm:
		var k: float = a.t / a.life
		var al := sin(k * PI)
		if a.get("glow", false):
			_glow_at(c, a.p, 7, Color(a.col, al))
		else:
			c.draw_circle(a.p, a.r, Color(a.col, al * 0.85))
	var won: bool = over != null and over.win
	var sw: float = Res.SHW[type] * L.mk * (0.6 if Res.FLY.has(type) else 1.0)
	var fade := 1.0 - (maxf(0.0, death_t - 1.05) / 0.6 if won else 0.0)
	_ellipse(c, Vector2(_mx, gy + 2), sw, sw * 0.22, Color(0, 0, 0, 0.38 * clampf(fade, 0, 1)))
	if t.get("boss", false):
		var r: float = 120.0 * L.mk
		_glow_at(c, Vector2(_mx, gy - 60.0 * L.mk), r, Color(1, 0.31, 0.12, 0.2 + _mp.get("wind", 0.0) * 0.3))
	var pk: float = L.pk
	_ellipse(c, Vector2(_hx + 3, gy + 2), 13.0 * pk, 3.5 * pk, Color(0, 0, 0, 0.35))
	if combo >= 10:
		var fr := 34.0 * pk * (1.0 + _pulse * 0.15)
		_glow_at(c, Vector2(_hx, gy - 26.0 * pk), fr, Color(1, 0.75, 0.3, 0.32))

func _draw_over() -> void:
	var c := over_n
	var gy: float = L.ground_y
	var pk: float = L.pk
	var won: bool = over != null and over.win
	# 혼이 빠져나가요
	if won and death_t > 0.95 and death_t < 2.0:
		var k := (death_t - 0.95) / 1.05
		_glow_at(c, Vector2(_mx, gy - cmeta.height * L.mk * 0.4 - k * 120.0), 26, Color(1, 1, 0.94, 0.8 * (1 - k)))
	# 공격 예고
	if _mp.get("wind", 0.0) > 0.05 and over == null:
		var top: float = gy - _fly - cmeta.height * L.mk - 16.0
		label(c, "!!" if _mp.heavy else "!", Vector2(_mx, top - _mp.wind * 6.0), Color("ff4a3a") if _mp.heavy else Color("ffb03a"), 26 + _mp.wind * 10)
	# 칼 궤적
	if trail.size() > 1:
		var col := Color(1, 0.84, 0.47) if (p_act != null and p_act.move == "finisher") or combo >= 10 else Color(0.88, 0.94, 1)
		for i in range(1, trail.size()):
			var al := float(i) / trail.size()
			c.draw_line(trail[i - 1].p, trail[i].p, Color(col, al * 0.75), maxf(1.0, al * 9.0 * pk / 2.0), true)
	# 방어 신호: 사냥꾼 둘레로 고리가 좁혀져요
	var hp0 := Vector2(_hx, gy - 26.0 * pk)
	for q in sigs:
		if q.res != "" and q.res != "early":
			continue
		var s0: float = q.t - q.lead
		if clock < s0 or clock > q.t + 0.2:
			continue
		var p := clampf((clock - s0) / q.lead, 0, 1)
		var r1 := 26.0 * pk
		var r := lerpf(r1 * 2.8, r1, p)
		var col := Color(1, 0.27, 0.2) if q.heavy else Color(1, 0.67, 0.24)
		_dashed_circle(c, hp0, r1, Color(1, 1, 1, 0.25 + p * 0.35))
		c.draw_arc(hp0, r, 0, TAU, 64, Color(col, 0.5 + p * 0.5), (6.0 if q.heavy else 4.0) * (1.0 - p * 0.3) + 1.0, true)
		if p > 0.55:
			label(c, "강공격! 방어(K)" if q.heavy else "방어(K)!", hp0 + Vector2(0, -r1 - 18), Color(Color("ff7a6a") if q.heavy else Color("ffd08a"), (p - 0.55) / 0.45), 16)
	# 효과
	for f in fx:
		var tt: float = f.t - f.d
		if tt < 0:
			continue
		var k: float = tt / f.life
		match f.k:
			"slash":
				var e := minf(1.0, k * 2.4)
				var b: float = f.a + (f.b - f.a) * e
				c.draw_set_transform_matrix(Transform2D(0, f.p) * Transform2D(0, Vector2(1, 0.5), 0, Vector2.ZERO) * Transform2D(f.a * 0.15, Vector2.ZERO))
				for i in 3:
					var a0: float = maxf(f.a, b - 1.5)
					if b - a0 > 0.01:
						c.draw_arc(Vector2.ZERO, f.r * (1.0 + i * 0.05), a0, b, 24, Color(f.col, (1.0 - k) * (1.0 - i * 0.3)), f.w * (1.0 - i * 0.35) * (1.0 - k * 0.5) * 1.4, true)
				c.draw_set_transform(Vector2.ZERO)
			"ring":
				var rr: float = f.r0 + (f.r1 - f.r0) * sqrt(k)
				var wd: float = f.w * (1.0 - k) + 0.5
				if f.get("flat", false):
					c.draw_set_transform(f.p, 0, Vector2(1, 0.22))
					c.draw_arc(Vector2.ZERO, rr, 0, TAU, 48, Color(f.col, 1.0 - k), wd / 0.22 * 0.5, true)
					c.draw_set_transform(Vector2.ZERO)
				else:
					c.draw_arc(f.p, rr, 0, TAU, 48, Color(f.col, 1.0 - k), wd, true)
			"lines":
				for i in 14:
					var a := float(i) / 14.0 * TAU + i
					var r0 := 40.0 + k * 30.0
					var r2 := 110.0 + k * 40.0
					c.draw_line(f.p + Vector2(cos(a), sin(a)) * r0, f.p + Vector2(cos(a), sin(a)) * r2, Color(1, 1, 1, 0.7 * (1.0 - k)), 2.0)
	for p in sp:
		if p.t < 0:
			continue
		var k: float = p.t / p.life
		match p.k:
			"line":
				c.draw_line(p.p, p.p - p.v * 0.03, Color(p.col, 1.0 - k), maxf(1.0, p.s * 0.7), true)
			"fire":
				c.draw_circle(p.p, p.s * (1.0 + k * 1.8), Color(p.col if k < 0.5 else Color("80391e"), (1.0 - k) * 0.7))
			"shard":
				var a: float = p.v.angle()
				c.draw_set_transform(p.p, a, Vector2.ONE)
				c.draw_colored_polygon(PackedVector2Array([Vector2(8, 0), Vector2(-4, -2.5), Vector2(-6, 0), Vector2(-4, 2.5)]), Color("e6f8ff", 1.0 - k * 0.5))
				c.draw_set_transform(Vector2.ZERO)
			"coin":
				pass
			_:
				c.draw_circle(p.p, p.s * (1.0 - k * 0.4), Color(p.col, (1.0 - k) * 0.95))
	for f in cf:
		var k: float = f.t
		var pop := 1.0 + maxf(0.0, 0.55 - k * 4.5)
		var a := 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
		label(c, f.txt, f.p + Vector2(f.vx * k, -34.0 * sqrt(k)), Color(f.col, a), f.size * pop)

func _dashed_circle(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var n := maxi(12, int(TAU * r / 11.0))
	for i in n:
		var a0 := float(i) / n * TAU
		c.draw_arc(p, r, a0, a0 + TAU / n * 0.55, 4, col, 2.0, true)

func _rr(c: CanvasItem, r: Rect2, col: Color, rad: float, border := Color(0, 0, 0, 0), bw := 0.0) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(int(rad))
	s.anti_aliasing = true
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(int(bw))
	c.draw_style_box(s, r)

func _draw_ui() -> void:
	var c := ui
	var W: float = L.W
	var H: float = L.H
	var ly: float = L.ly
	var sb: float = L.scene_b
	var fever := combo >= 10
	# 화면 효과
	if flash_w > 0:
		c.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, minf(1.0, flash_w * 2.0)))
	if red > 0:
		c.draw_texture_rect(_vign, Rect2(-W * 0.2, -H * 0.4, W * 1.4, H * 1.8), false, Color(1, 0.12, 0.2, minf(1.0, red * 1.2)))
	if fever:
		c.draw_texture_rect(_vign, Rect2(-W * 0.2, -sb * 0.4, W * 1.4, sb * 1.8), false, Color(1, 0.67, 0.16, 0.1 + _pulse * 0.1))
	if over != null and not over.win:
		c.draw_rect(Rect2(0, 0, W, H), Color(0.08, 0.08, 0.1, clampf(death_t / 0.7, 0, 1) * 0.45))
	# 아래 판
	for i in 8:
		var y0 := sb - 20.0 + i * 46.0 / 8.0
		c.draw_rect(Rect2(0, y0, W, 46.0 / 8.0 + 0.5), Color(0.027, 0.035, 0.063, 0.97 * (i + 1) / 8.0))
	c.draw_rect(Rect2(0, sb + 26, W, H), Color(0.027, 0.035, 0.063, 0.97))
	# 몬스터 이름판과 체력
	var hp_w := minf(340.0, W - 40.0)
	var hx0 := W / 2.0 - hp_w / 2.0
	var hy0 := 16.0
	_rr(c, Rect2(hx0 - 10, hy0 - 6, hp_w + 20, 46), Color(0.04, 0.05, 0.08, 0.72), 12)
	var boss: bool = t.get("boss", false)
	c.draw_string(Res.font_xbold, Vector2(hx0, hy0 + 11), t.n, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ffb36b") if boss else Color.WHITE)
	c.draw_string(Res.font_bold, Vector2(hx0, hy0 + 11), "%s · %d BPM" % [song.title, song.bpm], HORIZONTAL_ALIGNMENT_RIGHT, hp_w, 11, Color("9aa6b8"))
	_rr(c, Rect2(hx0, hy0 + 18, hp_w, 11), Color(1, 1, 1, 0.1), 5.5)
	_rr(c, Rect2(hx0, hy0 + 18, maxf(0.0, hp_w * hp_lag / t.hp), 11), Color(1, 0.94, 0.78, 0.85), 5.5)
	_rr(c, Rect2(hx0, hy0 + 18, maxf(0.0, hp_w * maxf(0.0, hp) / t.hp), 11), Color("e2405a"), 5.5)
	c.draw_rect(Rect2(hx0 + hp_w / 2 - 1, hy0 + 16, 2, 15), Color(1, 1, 1, 0.7))
	if phase2:
		c.draw_string(Res.font_xbold, Vector2(hx0 + hp_w + 6, hy0 + 28), "분노", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ff7a6a"))
	# ---- 공격 레인 ----
	var hit_x := maxf(70.0, W * 0.13)
	var ex := W - 18.0
	var speed := (ex - hit_x) / APPROACH
	var lh := 25.0
	_rr(c, Rect2(14, ly - lh, W - 28, lh * 2), Color(1, 0.36, 0.42, 0.1), lh, Color(1, 0.82, 0.43, 0.45 + _pulse * 0.4) if fever else Color(1, 0.36, 0.42, 0.35), 2)
	var b0 := floori((clock - 0.3) / beat)
	var b1 := ceili((clock + APPROACH) / beat)
	for b in range(maxi(0, b0), b1 + 1):
		var x := hit_x + (b * beat - clock) * speed
		if x < 16 or x > ex:
			continue
		var bar := b % bpb == 0
		c.draw_line(Vector2(x, ly - lh + 3), Vector2(x, ly + lh - 3), Color(1, 1, 1, 0.2 if bar else 0.07), 2.0 if bar else 1.0)
	var fa := flash_a / 0.12
	_glow_at(c, Vector2(hit_x, ly), 36, Color(1, 0.36, 0.42, 0.25 + fa * 0.5 + _pulse * 0.12))
	var rr := 20.0 + _pulse * 2.5 + fa * 3.0
	c.draw_circle(Vector2(hit_x, ly), rr, Color(1, 0.78, 0.31, 0.35) if holding else Color(0, 0, 0, 0.45))
	c.draw_arc(Vector2(hit_x, ly), rr, 0, TAU, 40, Color("ffd34d") if holding else Color("ff5d6c"), 3.0, true)
	label(c, "J", Vector2(hit_x, ly), Color(1, 1, 1, 0.6), 15)
	if over == null:
		for n in notes:
			if n.st == 2 and n.get("hit", false) and n.k == "tap":
				var k: float = n.ht / 0.3
				if k >= 1.0:
					continue
				c.draw_arc(Vector2(hit_x, ly), 20 + k * 30, 0, TAU, 40, Color(1, 0.47, 0.51, 1.0 - k), 4.0 * (1.0 - k) + 1.0, true)
				continue
			if n.st == 2 and not n.get("missed", false) and n.k != "trap":
				continue
			var x := maxf(hit_x if n.st == 1 else -99.0, hit_x + (n.t - clock) * speed)
			if x > ex + 20:
				continue
			var fade := 0.35 if n.get("missed", false) or n.get("dodged", false) else 1.0
			if n.k == "hold":
				var x2 := minf(ex, hit_x + (n.end - clock) * speed)
				if x2 > x:
					var hc := Color("ffd060") if n.st == 1 else Color("e8955a")
					_rr(c, Rect2(x, ly - 9, x2 - x, 18), Color(hc, fade), 9, Color(1, 1, 1, 0.8 * fade), 2)
					c.draw_circle(Vector2(x2, ly), 10, Color(Color("ffb84a"), fade))
					c.draw_arc(Vector2(x2, ly), 10, 0, TAU, 24, Color(1, 1, 1, fade), 2.0, true)
			if n.k == "trap":
				var pts := PackedVector2Array()
				for i in 16:
					var rad := 10.0 if i % 2 else 17.0
					var a := float(i) / 16.0 * TAU + clock * 3.0
					pts.append(Vector2(x, ly) + Vector2(cos(a), sin(a)) * rad)
				c.draw_colored_polygon(pts, Color(Color("7a3cae"), fade))
				pts.append(pts[0])
				c.draw_polyline(pts, Color(Color("1a0a2a"), fade), 1.5, true)
				c.draw_circle(Vector2(x, ly), 7, Color(Color("d8a8ff"), fade * 0.8))
				c.draw_line(Vector2(x - 5, ly - 5), Vector2(x + 5, ly + 5), Color(1, 1, 1, fade), 2.6)
				c.draw_line(Vector2(x + 5, ly - 5), Vector2(x - 5, ly + 5), Color(1, 1, 1, fade), 2.6)
				if x > hit_x and x < hit_x + 220:
					label(c, "누르지 마!", Vector2(x, ly - 30), Color(Color("d9a8ff"), fade), 12)
			else:
				var hold: bool = n.k == "hold"
				_glow_at(c, Vector2(x, ly), 26, Color(1, 0.36, 0.42, 0.55 * fade))
				c.draw_circle(Vector2(x, ly), 15, Color(Color("f0a030") if hold else Color("e0344a"), fade))
				c.draw_circle(Vector2(x - 4, ly - 4), 7, Color(Color("ffe3a0") if hold else Color("ffb3ba"), 0.6 * fade))
				c.draw_arc(Vector2(x, ly), 15, 0, TAU, 32, Color(1, 1, 1, fade), 2.5, true)
				label(c, "꾹" if hold else "J", Vector2(x, ly + 1), Color(1, 1, 1, fade), 13)
	if judg_t > 0:
		label(c, judg, Vector2(hit_x + 74, ly - 40 - (0.6 - judg_t) * 20), Color(judg_col, minf(1.0, judg_t * 3.0)), 24 + maxf(0.0, judg_t - 0.45) * 40)
	if combo >= 2:
		label(c, "%d 콤보" % combo, Vector2(W - 70, ly - 40), Color("ffe27a") if fever else Color.WHITE, 20 + minf(10.0, combo / 4.0) + _pulse * 4)
	# 사냥꾼 체력
	var pw := minf(320.0, W - 60.0)
	var py: float = ly + lh + 14
	var mh := float(Game.max_hp())
	_rr(c, Rect2(W / 2 - pw / 2, py, pw, 13), Color(1, 1, 1, 0.1), 6.5)
	_rr(c, Rect2(W / 2 - pw / 2, py, maxf(0.0, pw * p_lag / mh), 13), Color(1, 0.47, 0.47, 0.7), 6.5)
	_rr(c, Rect2(W / 2 - pw / 2, py, maxf(0.0, pw * maxf(0.0, Game.S.hp) / mh), 13), Color("3fc46f"), 6.5)
	label(c, "체력 %d / %d    공격력 %d" % [maxi(0, ceili(Game.S.hp)), int(mh), Game.ST.dmg], Vector2(W / 2, py + 6.5), Color.WHITE, 11)
	label(c, "J 탭 · 노란 막대는 꾹 · 보라 가시는 누르지 마 · 고리가 좁혀지면 K", Vector2(W / 2, py + 26), Color("8a96a8"), 11)
	# 카운트인
	if clock < bar_dur and over == null:
		var b := floori(maxf(0.0, clock) / beat)
		var last := bpb - 1
		var txt := str(last - b) if b < last else "FIGHT!"
		label(c, txt, Vector2(W / 2, sb * 0.5), Color(Color.WHITE if b < last else Color("ffe27a"), 1.0 - _phase * 0.7), (52 if b < last else 62) * (1.0 + (1.0 - _phase) * 0.25))
		label(c, "%s이(가) 나타났다!" % t.n, Vector2(W / 2, sb * 0.5 - 56), Color(Color("ffb36b") if boss else Color("ffd9a0"), minf(1.0, intro * 2.0)), 18)
	for f in fx:
		if f.k == "banner":
			var k: float = f.t / f.life
			var s := 1.0 + maxf(0.0, 0.3 - k) * 2.0
			var rg: bool = f.txt.begins_with("분노")
			label(c, f.txt, Vector2(W / 2, sb * 0.3), Color(Color("ff6a5a") if rg else Color("ffe27a"), 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3), (40 if rg else 34) * s)
	# 날아가는 동전 (화면 위 UI 기준)
	for p in sp:
		if p.k == "coin" and p.t >= 0:
			var sx := absf(cos(p.t * 14.0)) * 5.0 + 1.0
			_ellipse(c, p.p, sx, 5, Color("ffd24a"))
	# 등장 막
	if intro < 1:
		var bh := (1.0 - _ein) * H * 0.5
		c.draw_rect(Rect2(0, 0, W, bh), Color.BLACK)
		c.draw_rect(Rect2(0, H - bh, W, bh), Color.BLACK)
