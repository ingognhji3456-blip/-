extends Node2D
## 넓은 필드: 땅, 나무·바위(채집), 마을 건물, 사냥꾼, 몬스터

const MonsterScript := preload("res://scripts/monster.gd")
const BattleScene := preload("res://scenes/battle.tscn")
const BK := 256.0
const NODE_SHADOW := {"tree": [22, 4, 34, 12], "rock": [6, 2, 24, 8], "ore": [6, 2, 27, 9], "crystal": [6, 2, 20, 7], "herb": [3, 1, 12, 4], "shroom": [3, 1, 12, 4], "ice": [6, 2, 20, 7], "cactus": [12, 2, 16, 5], "goldore": [6, 2, 27, 9], "lotus": [3, 1, 12, 4]}
const BURST_COL := {"tree": "7a5a2e", "crystal": "9fe6ff", "herb": "7fd36b", "shroom": "c98a5a", "ice": "dff6ff", "cactus": "6fa34a", "goldore": "ffd24a", "lotus": "ffb3d0"}

var WS: float
var CX: float
var CY: float
var time := 0.0
var ents: Node2D
var fx
var hud
var panels
var cam: Camera2D
var player: Node2D
var p_spr: AnimatedSprite2D
var P := {"face": 1, "view": "down", "moving": false, "home": 0.0, "swing": 0.0, "hurt": 0.0, "target": {}, "move_to": null, "stuck": 0.0, "pet_t": 0.0, "anim": 0.0}
var ppos := Vector2.ZERO
var pzone := 0
var nodes: Array = []
var grid := {}
var mons: Array = []
var grace := 1.5
var last_bld := ""
var spawn_t := 0.0
var save_t := 5.0
var boss_t := 0.0
var pet_beam = null
var battle: Node = null
var dragging := false
var _tree_faded: Array = []

func _ready() -> void:
	var w: Dictionary = Game.D.world
	WS = w.size
	CX = w.cx
	CY = w.cy
	_make_terrain()
	ents = Node2D.new()
	ents.y_sort_enabled = true
	add_child(ents)
	fx = preload("res://scripts/world_fx.gd").new()
	fx.w = self
	fx.z_index = 50
	add_child(fx)
	_make_props()
	_make_player()
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WS)
	cam.limit_bottom = int(WS)
	cam.position = ppos
	add_child(cam)
	cam.make_current()
	for s in Game.D.spawn:
		for i in int(s[1]) * 2:
			if _count(s[0]) >= int(s[1]):
				break
			_spawn_mon(s[0])
	hud = preload("res://scripts/hud.gd").new()
	hud.w = self
	add_child(hud)
	panels = preload("res://scripts/panels.gd").new()
	panels.w = self
	add_child(panels)
	if not Game.S.seen_help:
		panels.open("help")

# ---------------- 만들기 ----------------
func _make_terrain() -> void:
	var t := Sprite2D.new()
	t.texture = Res.tex("res://assets/terrain/color.png")
	t.centered = false
	var s: float = WS / t.texture.get_width()
	t.scale = Vector2(s, s)
	t.z_index = -10
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("info_tex", Res.tex("res://assets/terrain/info.png"))
	for z in 7:
		m.set_shader_parameter("det%d" % z, Res.tex("res://assets/terrain/detail_%d.png" % z))
	m.set_shader_parameter("world_size", WS)
	m.set_shader_parameter("lair", Vector2(Game.D.world.lair.x, Game.D.world.lair.y))
	t.material = m
	add_child(t)

func _shadow_at(parent: Node2D, ox: float, oy: float, w: float, h: float, a := 0.26) -> void:
	var sh := Res.make_shadow(w, h)
	sh.position = Vector2(ox, oy)
	sh.modulate.a = a / 0.42 * 0.9
	parent.add_child(sh)

func _make_props() -> void:
	for o in Game.D.world.decos:
		var k: String = o[0]
		if not Res.props_meta.has(k):
			continue
		var holder := Node2D.new()
		holder.position = Vector2(o[1], o[2])
		if k == "lamp":
			_shadow_at(holder, 8, 1, 10, 3, 0.25)
		elif k.begins_with("bush") or k == "sbush":
			_shadow_at(holder, 5, 1, 22, 7, 0.22)
		elif k == "dead" or k == "pillar" or k.begins_with("dtree"):
			_shadow_at(holder, 12, 2, 20, 6, 0.24)
		elif k == "barrel" or k == "crate":
			_shadow_at(holder, 5, 1, 12, 4, 0.25)
		holder.add_child(Res.prop_sprite(k))
		ents.add_child(holder)
		if k == "dead" or k == "pillar":
			_bucket(holder.position).append({"deco": holder, "pos": holder.position, "type": "_deco", "dead": false})
	for a in Game.D.world.nodes:
		var n := {"type": a[0], "v": a[1], "pos": Vector2(a[2], a[3]), "hp": float(Game.D.nodeTypes[a[0]].hp), "dead": false, "resp": 0.0, "shake": 0.0}
		var holder := Node2D.new()
		holder.position = n.pos
		var s: Array = NODE_SHADOW[n.type]
		_shadow_at(holder, s[0], s[1], s[2], s[3], 0.26)
		var spr := Res.prop_sprite(n.v)
		holder.add_child(spr)
		if n.type == "tree":
			var stump := Res.prop_sprite("stump")
			stump.visible = false
			holder.add_child(stump)
			n.alt = stump
		elif n.type == "rock" or n.type == "ore":
			var rb := Res.prop_sprite("rubble")
			rb.visible = false
			rb.modulate.a = 0.7
			holder.add_child(rb)
			n.alt = rb
		n.node = holder
		n.spr = spr
		ents.add_child(holder)
		nodes.append(n)
		_bucket(n.pos).append(n)
	for b in Game.D.world.buildings:
		var h := Node2D.new()
		h.position = Vector2(b.x, b.y)
		h.add_child(Res.prop_sprite("bld_" + b.id))
		ents.add_child(h)
	var f := Node2D.new()
	f.position = Vector2(CX, CY)
	f.add_child(Res.prop_sprite("fountain"))
	ents.add_child(f)

func _bucket(p: Vector2) -> Array:
	var key := Vector2i(int(p.x / BK), int(p.y / BK))
	if not grid.has(key):
		grid[key] = []
	return grid[key]

func nodes_near(p: Vector2, r: float) -> Array:
	var out := []
	var r0 := Vector2i(int((p.x - r) / BK), int((p.y - r) / BK))
	var r1 := Vector2i(int((p.x + r) / BK), int((p.y + r) / BK))
	for j in range(r0.y, r1.y + 1):
		for i in range(r0.x, r1.x + 1):
			var key := Vector2i(i, j)
			if grid.has(key):
				for n in grid[key]:
					if n.type != "_deco":
						out.append(n)
	return out

func _make_player() -> void:
	player = Node2D.new()
	ppos = Vector2(Game.S.x, Game.S.y)
	if not Game.walkable(ppos.x, ppos.y) or _in_bld(ppos, 12):
		ppos = Vector2(CX, CY + 70)
	player.position = ppos
	var sh := Res.make_shadow(13, 4)
	sh.position = Vector2(2, 1)
	player.add_child(sh)
	p_spr = AnimatedSprite2D.new()
	p_spr.sprite_frames = Res.hero_world_frames()
	p_spr.centered = false
	var m: Dictionary = Res.hero_meta.world
	p_spr.offset = -Vector2(m.ox, m.oy)
	p_spr.scale = Vector2.ONE / float(m.ps)
	p_spr.play("down_idle")
	player.add_child(p_spr)
	ents.add_child(player)

func _count(type: String) -> int:
	var c := 0
	for m in mons:
		if m.type == type and not m.dead:
			c += 1
	return c

func _rand_pos(z: int, deep) -> Vector2:
	var zr: Array = Game.D.world.zr
	var rmin: float = zr[0] if z == 1 else zr[1] - 100 if z == 2 else zr[2] - 100
	var rmax: float = zr[1] + 100 if z == 1 else zr[2] + 100 if z == 2 else 5700.0
	var deep_r: float = Game.D.world.deep
	for k in 400:
		var a := randf() * TAU
		var r := sqrt(randf_range(rmin * rmin, rmax * rmax))
		var p := Vector2(CX + cos(a) * r, CY + sin(a) * r)
		if p.x < 60 or p.y < 60 or p.x > WS - 60 or p.y > WS - 60:
			continue
		if Game.zone_at(p.x, p.y) != z:
			continue
		if deep != null and (r >= deep_r) != deep:
			continue
		if _in_bld(p, 30) or Game.near_water(p.x, p.y, 24):
			continue
		return p
	return Vector2(CX + zr[0] + 60, CY + 30)

func _add_mon(type: String, p: Vector2, home = null) -> void:
	var m := Node2D.new()
	m.set_script(MonsterScript)
	m.setup(type, p)
	if home != null:
		m.home = home
	ents.add_child(m)
	mons.append(m)

func _spawn_mon(type: String) -> void:
	var t: Dictionary = Game.D.monsters[type]
	var lair := Vector2(Game.D.world.lair.x, Game.D.world.lair.y)
	for k in 30:
		var p := _rand_pos(int(t.zone), t.get("deep"))
		if p.distance_to(ppos) > 520 and p.distance_to(lair) > 260:
			_add_mon(type, p)
			if type == "wolf":  # 늑대는 무리 지어 다녀요
				for i in randi_range(1, 2):
					var q := p + Vector2(randf_range(-50, 50), randf_range(-50, 50))
					if Game.walkable(q.x, q.y):
						_add_mon("wolf", q, p)
			return

# ---------------- 도우미 ----------------
func _in_bld(p: Vector2, pad := 0.0) -> bool:
	for b in Game.D.world.buildings:
		if p.x > b.x - 50 - pad and p.x < b.x + 50 + pad and p.y > b.y - 30 - pad and p.y < b.y + 34 + pad:
			return true
	return false

func _door(b: Dictionary) -> Vector2:
	return Vector2(b.x, b.y + 50)

func _push_out(p: Vector2, r: float) -> Vector2:
	for b in Game.D.world.buildings:
		var x1: float = b.x - 50 - r
		var x2: float = b.x + 50 + r
		var y1: float = b.y - 30 - r
		var y2: float = b.y + 34 + r
		if p.x > x1 and p.x < x2 and p.y > y1 and p.y < y2:
			var dl := p.x - x1
			var dr := x2 - p.x
			var dtp := p.y - y1
			var db := y2 - p.y
			var m := minf(minf(dl, dr), minf(dtp, db))
			if m == dl: p.x = x1
			elif m == dr: p.x = x2
			elif m == dtp: p.y = y1
			else: p.y = y2
	var c := Vector2(CX, CY)
	if p.distance_to(c) < 40 + r:
		p = c + (p - c).normalized() * (40 + r)
	return p.clamp(Vector2(20, 20), Vector2(WS - 20, WS - 20))

func view_rect() -> Rect2:
	var vs := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - vs / 2, vs)

func busy() -> bool:
	return battle != null or panels.is_open()

func toast(msg: String, kind := "") -> void:
	hud.toast(msg, kind)

# ---------------- 입력 ----------------
func _unhandled_input(e: InputEvent) -> void:
	if busy():
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var wp := get_global_mouse_position()
			var h := _pick_at(wp)
			if h:
				_interact(h)
			else:
				P.target = {}
				P.move_to = wp
				fx.marker = {"p": wp, "t": 0.6}
				dragging = true
		else:
			dragging = false
	elif e is InputEventMouseMotion and dragging:
		P.move_to = get_global_mouse_position()
		P.target = {}
	elif e.is_action_pressed("attack"):
		_key_interact()
	elif e.is_action_pressed("potion"):
		use_potion()
	elif e.is_action_pressed("home"):
		go_home()
	elif e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_I:
		panels.open("bag")

func _pick_at(p: Vector2) -> Dictionary:
	for b in Game.D.world.buildings:
		if p.x > b.x - 54 and p.x < b.x + 54 and p.y > b.y - 66 and p.y < b.y + 40:
			return {"kind": "bld", "ref": b}
	var best := {}
	var bd := 1e9
	for m in mons:
		if m.dead or not m.visible:
			continue
		var d: float = p.distance_to(m.position - Vector2(0, (34.0 if m.type == "bat" else m.t.size * 0.4)))
		if d < m.t.size * 0.65 + 6 and d < bd:
			bd = d
			best = {"kind": "mon", "ref": m}
	if best:
		return best
	for n in nodes_near(p, 130):
		if n.dead:
			continue
		var nd: Dictionary = Game.D.nodeTypes[n.type]
		var d2: float = p.distance_to(n.pos - Vector2(0, nd.py))
		if d2 < nd.pr and d2 < bd:
			bd = d2
			best = {"kind": "node", "ref": n}
	return best

func _interact(h: Dictionary) -> void:
	var r = h.ref
	if h.kind == "node":
		if ppos.distance_to(r.pos) <= 64:
			gather_hit(r)
			return
		P.target = h
		P.move_to = r.pos
	elif h.kind == "mon":
		if ppos.distance_to(r.position) <= 44:
			start_battle(r)
			return
		P.target = h
		P.move_to = r.position
	else:
		var d := _door(r)
		if ppos.distance_to(d) <= 50:
			last_bld = r.id
			panels.open(r.id)
			return
		P.target = h
		P.move_to = d

## 키보드로: 가장 가까운 몬스터·자원·건물에 손을 써요
func _key_interact() -> void:
	for m in mons:
		if not m.dead and m.visible and ppos.distance_to(m.position) < 64:
			start_battle(m)
			return
	var best = null
	var bd := 70.0
	for n in nodes_near(ppos, 80):
		if n.dead:
			continue
		var d: float = ppos.distance_to(n.pos)
		if d < bd:
			bd = d
			best = n
	if best:
		gather_hit(best)
		return
	for b in Game.D.world.buildings:
		if ppos.distance_to(_door(b)) < 60:
			last_bld = b.id
			panels.open(b.id)
			return

# ---------------- 행동 ----------------
func gather_hit(n: Dictionary, auto := false) -> void:
	var d: Dictionary = Game.D.nodeTypes[n.type]
	n.hp -= maxf(1.0, Game.ST.power * 0.6) if auto else Game.ST.power
	n.shake = 0.18
	if not auto:
		P.swing = 0.22
		P.face = 1 if n.pos.x >= ppos.x else -1
		Res.sfx(d.snd)
	fx.burst(n.pos - Vector2(0, d.top * 0.45), Color(BURST_COL.get(n.type, "9a9a9a")), 5, 90)
	if n.hp <= 0:
		n.dead = true
		n.resp = d.resp * randf_range(0.85, 1.15)
		n.spr.visible = false
		if n.has("alt"):
			n.alt.visible = true
		var dbl: bool = randf() < Game.ST.dbl
		var ly: float = n.pos.y - d.top
		for dr in d.drop:
			var amt: int = (randi_range(dr[1], dr[2]) + Game.ST.extra) * (2 if dbl else 1)
			Game.add_mat(dr[0], amt)
			fx.float_text(Vector2(n.pos.x, ly), "+%d %s%s" % [amt, Game.mat_name(dr[0]), " ×2" if dbl else ""], Color("ffe27a") if dbl else Color.WHITE)
			ly -= 20
		fx.burst(n.pos - Vector2(0, 10), Color("fff3b0"), 12, 160)

func use_potion() -> void:
	if Game.S.potions <= 0:
		toast("물약이 없어요. 잡화점에서 사요.", "bad")
		return
	if Game.S.hp >= Game.max_hp():
		toast("체력이 가득해요")
		return
	Game.S.potions -= 1
	var h := roundi(Game.max_hp() * 0.5)
	Game.S.hp = minf(Game.max_hp(), Game.S.hp + h)
	Res.sfx("potion")
	if battle:
		battle.on_potion(h)
	else:
		fx.float_text(ppos + Vector2(0, -40), "+%d" % h, Color("5fdc8a"))

func go_home() -> void:
	if busy() or P.home > 0:
		return
	if pzone == 0:
		toast("이미 마을이에요")
		return
	P.home = 2.0
	P.move_to = null
	P.target = {}
	toast("2초 뒤 마을로 귀환해요 (움직이면 취소)")

func start_battle(m) -> void:
	if battle or m.dead:
		return
	P.move_to = null
	P.target = {}
	dragging = false
	Game.in_battle = true
	battle = BattleScene.instantiate()
	battle.finished.connect(_on_battle_finished)
	add_child(battle)
	hud.set_battle(true)
	battle.start(m, self)

func _on_battle_finished(result: String, m) -> void:
	battle.queue_free()
	battle = null
	Game.in_battle = false
	hud.set_battle(false)
	if result == "win":
		m.dead = true
		mons.erase(m)
		m.queue_free()
		if m.t.get("boss", false):
			boss_t = 240.0
		grace = 2.5
	elif result == "lose":
		ppos = Vector2(CX, CY + 70)
		Game.S.hp = Game.max_hp()
		cam.position = ppos
		cam.reset_smoothing()
		grace = 2.5
	else:  # 도망
		var a: float = (ppos - m.position).angle()
		var np := ppos + Vector2(cos(a), sin(a)) * 70
		if Game.walkable(np.x, np.y):
			ppos = np
		grace = 3.0
		toast("도망쳤어요")
	player.position = ppos
	_save()

func _save() -> void:
	Game.S.x = ppos.x
	Game.S.y = ppos.y
	Game.save_game()

# ---------------- 매 프레임 ----------------
func _process(dt: float) -> void:
	time += dt
	fx.step(dt)
	P.swing = maxf(0.0, P.swing - dt)
	hud.refresh()
	if battle:
		return
	if panels.is_open():
		P.moving = false
		_anim_player(Vector2.ZERO, false)
		return
	grace = maxf(0.0, grace - dt)
	_move_player(dt)
	pzone = Game.zone_at(ppos.x, ppos.y)
	if pzone == 0 and Game.S.hp < Game.max_hp():
		Game.S.hp = minf(Game.max_hp(), Game.S.hp + Game.max_hp() * 0.06 * dt)
	# 건물 문 앞에 서면 들어가요
	for b in Game.D.world.buildings:
		var d := ppos.distance_to(_door(b))
		if d < 30 and last_bld != b.id:
			last_bld = b.id
			Res.sfx("door")
			panels.open(b.id)
			return
		if d > 56 and last_bld == b.id:
			last_bld = ""
	_ambience(dt)
	_update_nodes(dt)
	_update_pet(dt)
	for m in mons.duplicate():
		if m.dead:
			continue
		if m.think(dt, self):
			start_battle(m)
			return
	spawn_t -= dt
	if spawn_t <= 0:
		spawn_t = 2.0
		for s in Game.D.spawn:
			if _count(s[0]) < int(s[1]):
				_spawn_mon(s[0])
	if _count("dragon") == 0:
		boss_t -= dt
		var lair := Vector2(Game.D.world.lair.x, Game.D.world.lair.y)
		if boss_t <= 0 and ppos.distance_to(lair) > 400:
			_add_mon("dragon", lair)
	save_t -= dt
	if save_t <= 0:
		save_t = 5.0
		_save()

func _move_player(dt: float) -> void:
	var dv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dv != Vector2.ZERO:
		P.target = {}
		P.move_to = null
		fx.marker = {}
	elif P.move_to != null:
		var tg: Dictionary = P.target
		if tg:
			if tg.kind == "bld":
				P.move_to = _door(tg.ref)
			elif tg.kind == "mon":
				P.move_to = tg.ref.position
				if tg.ref.dead:
					P.target = {}
					P.move_to = null
			else:
				P.move_to = tg.ref.pos
				if tg.ref.dead:
					P.target = {}
					P.move_to = null
		if P.move_to != null:
			var to: Vector2 = P.move_to - ppos
			var d := to.length()
			var arrive := 6.0
			if tg:
				arrive = 50.0 if tg.kind == "node" else 36.0 if tg.kind == "mon" else 14.0
			if d <= arrive:
				P.move_to = null
				P.target = {}
				if tg:
					if tg.kind == "node":
						gather_hit(tg.ref)
					elif tg.kind == "mon":
						start_battle(tg.ref)
						return
			else:
				dv = to / d
	if dv != Vector2.ZERO and P.home > 0:
		P.home = 0.0
		toast("귀환을 멈췄어요")
	if P.home > 0:
		P.home -= dt
		if randf() < dt * 30:
			fx.add_amb({"k": "spark", "p": ppos + Vector2(randf_range(-16, 16), -randf_range(0, 40)), "r": randf_range(2, 5), "life": 0.6})
		if P.home <= 0:
			P.home = 0.0
			ppos = Vector2(CX, CY + 70)
			cam.position = ppos
			cam.reset_smoothing()
			fx.burst(ppos - Vector2(0, 20), Color("bfe9ff"), 20, 140)
			Res.sfx("lvl", -6.0)
			toast("마을로 돌아왔어요", "good")
	P.moving = false
	if dv != Vector2.ZERO:
		dv = dv.normalized()
		var far: bool = P.move_to != null and not P.target and ppos.distance_to(P.move_to) > 380
		var sprint: bool = Input.is_action_pressed("sprint") or far
		var sp: float = Game.ST.spd * (1.5 if sprint else 1.0) * dt
		var old := ppos
		var np := ppos + dv * sp
		if Game.walkable(np.x, np.y):
			ppos = np
		elif Game.walkable(np.x, ppos.y):
			ppos.x = np.x
		elif Game.walkable(ppos.x, np.y):
			ppos.y = np.y
		ppos = _push_out(ppos, 12)
		var moved := ppos.distance_to(old)
		P.moving = moved > sp * 0.2
		if P.move_to != null and not P.moving:
			P.stuck += dt
			if P.stuck > 0.3:
				P.move_to = null
				P.target = {}
				P.stuck = 0.0
		else:
			P.stuck = 0.0
		if absf(dv.y) > absf(dv.x) * 1.15:
			P.view = "up" if dv.y < 0 else "down"
		else:
			P.view = "side"
			P.face = 1 if dv.x > 0 else -1
		if P.moving:
			var st: float = signf(sin(P.anim))
			P.anim += dt * Game.ST.spd * (1.5 if sprint else 1.0) / 15.0
			if signf(sin(P.anim)) != st:
				fx.add_amb({"k": "dust", "p": ppos + Vector2(randf_range(-3, 3), randf_range(-1, 2)), "v": Vector2(-dv.x * 14 + randf_range(-8, 8), randf_range(-10, -2)), "r": randf_range(2, 3.5), "life": randf_range(0.35, 0.55)})
		p_spr.speed_scale = 1.5 if sprint else 1.0
	player.position = ppos
	_anim_player(dv, P.moving)
	cam.position = cam.position.lerp(ppos, minf(1.0, dt * 8.0))
	# 나무 뒤에 숨으면 나무가 반투명해져요
	for n in _tree_faded:
		n.node.modulate.a = 1.0
	_tree_faded.clear()
	for key in [Vector2i(int(ppos.x / BK), int(ppos.y / BK)), Vector2i(int(ppos.x / BK), int((ppos.y + 110) / BK))]:
		if not grid.has(key):
			continue
		for n in grid[key]:
			var tall: float = 112.0 if n.type == "tree" else 80.0 if n.type == "_deco" else 0.0
			if tall > 0 and not n.dead and ppos.y < n.pos.y - 4 and ppos.y > n.pos.y - tall and absf(ppos.x - n.pos.x) < (42.0 if n.type == "tree" else 26.0):
				var nd: Node2D = n.node if n.has("node") else n.deco
				if not n.has("node"):
					n.node = nd
				nd.modulate.a = 0.45
				_tree_faded.append(n)

func _anim_player(dv: Vector2, moving: bool) -> void:
	var a: String
	if P.swing > 0:
		a = "side_swing"
	elif moving:
		a = P.view + "_walk"
	else:
		a = P.view + "_idle"
	if p_spr.animation != a:
		p_spr.play(a)
	elif not p_spr.is_playing():
		p_spr.play(a)
	p_spr.flip_h = P.face < 0 and (P.view == "side" or P.swing > 0)
	p_spr.modulate = Color(1, 0.5, 0.5) if P.hurt > 0 else Color.WHITE

func _update_nodes(dt: float) -> void:
	for n in nodes_near(ppos, 900):
		if n.shake > 0:
			n.shake = maxf(0.0, n.shake - dt)
			n.spr.position.x = sin(n.shake * 90.0) * 3.0
		if not n.dead and n.hp < Game.D.nodeTypes[n.type].hp:
			n.hp = minf(Game.D.nodeTypes[n.type].hp, n.hp + dt * 0.3)
	# 다시 자라기 (전체를 가끔씩)
	var step := int(time * 60.0) % 8
	for i in range(step, nodes.size(), 8):
		var n: Dictionary = nodes[i]
		if n.dead:
			n.resp -= dt * 8.0
			if n.resp <= 0 and n.pos.distance_to(ppos) > 60:
				n.dead = false
				n.hp = float(Game.D.nodeTypes[n.type].hp)
				n.spr.visible = true
				if n.has("alt"):
					n.alt.visible = false

func _update_pet(dt: float) -> void:
	if pet_beam:
		pet_beam.t -= dt
		if pet_beam.t <= 0:
			pet_beam = null
	if Game.ST.pet <= 0:
		return
	P.pet_t -= dt
	if P.pet_t <= 0:
		P.pet_t = 2.4 / Game.ST.pet
		var best = null
		var bd := 170.0
		for n in nodes_near(ppos, 170):
			if n.dead:
				continue
			var d: float = n.pos.distance_to(ppos)
			if d < bd:
				bd = d
				best = n
		if best:
			gather_hit(best, true)
			pet_beam = {"p": best.pos - Vector2(0, Game.D.nodeTypes[best.type].top * 0.5), "t": 0.3}

func _ambience(dt: float) -> void:
	for b in Game.D.world.buildings:
		if randf() < dt * 4:
			fx.add_amb({"k": "smoke", "p": Vector2(b.x + 28 + randf_range(-2, 2), b.y - 90), "v": Vector2(randf_range(4, 12), randf_range(-22, -14)), "r": randf_range(3, 5), "life": randf_range(2, 3)})
	var vr := view_rect()
	for i in 3:
		var p := Vector2(randf_range(vr.position.x, vr.end.x), randf_range(vr.position.y, vr.end.y))
		if Game.is_water(p.x, p.y) and Game.is_water(p.x + 16, p.y):
			fx.add_amb({"k": "spark", "p": p, "r": randf_range(3, 7), "life": randf_range(0.6, 1.2)})
			continue
		var z := Game.zone_at(p.x, p.y)
		if (z == 2 or z == 6) and randf() < 0.25:
			fx.add_amb({"k": "fly", "p": p, "v": Vector2(randf_range(-8, 8), randf_range(-8, 8)), "r": 1.6, "life": randf_range(2, 4)})
		elif z == 4 and randf() < 0.9:
			fx.add_amb({"k": "snow", "p": p - Vector2(0, 80), "v": Vector2(randf_range(8, 22), randf_range(22, 40)), "r": randf_range(1, 2.4), "life": randf_range(2.5, 4)})
		elif z == 5 and randf() < 0.2:
			fx.add_amb({"k": "dust", "p": p, "v": Vector2(randf_range(20, 40), randf_range(-3, 3)), "r": randf_range(2, 4), "life": randf_range(1.5, 2.5)})
		elif z == 6 and randf() < 0.12:
			fx.add_amb({"k": "mist", "p": p, "v": Vector2(randf_range(4, 10), 0), "r": randf_range(30, 60), "life": randf_range(4, 6)})

func on_level_up(n: int) -> void:
	toast("레벨 업! Lv %d (공격력·체력 증가)" % Game.S.lv, "gold")
	Res.sfx("lvl")
