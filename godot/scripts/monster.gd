extends Node2D
## 들판을 돌아다니는 몬스터 하나. 돌아다니기 / 쫓기 / 도망가기 (웹판 AI를 옮겼어요)

var type: String
var t: Dictionary
var home: Vector2
var hp: float
var dir := Vector2.ZERO
var wt := 0.0
var face := 1.0
var face_s := 1.0
var anim := 0.0
var chase := false
var flee := false
var dead := false
var mv := false
var seed := 0.0
var born := 0.0
var alert_t := 0.0
var emerge := 0.0
var lift := 0.0
var spr: AnimatedSprite2D
var shadow: Sprite2D
var _mat: ShaderMaterial
var _base := 1.0

static var _mat_calm: ShaderMaterial
static var _mat_angry: ShaderMaterial

func setup(kind: String, pos: Vector2) -> void:
	type = kind
	t = Game.D.monsters[kind]
	position = pos
	home = pos
	hp = t.hp
	seed = randf() * 100.0
	face = 1.0 if randf() < 0.5 else -1.0
	face_s = face
	anim = randf() * 6.0
	var meta: Dictionary = Res.creature_meta[kind]
	var k: float = Res.WSCALE[kind]
	var sw: float = Res.SHW[kind] * k * (0.6 if Res.FLY.has(kind) else 1.0)
	shadow = Res.make_shadow(sw, sw * 0.32)
	shadow.position = Vector2(4, 1)
	add_child(shadow)
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = Res.creature_frames(kind)
	spr.centered = false
	spr.offset = -Vector2(meta.ox, meta.oy)
	_base = k / float(meta.ps)
	spr.scale = Vector2(_base * face_s, _base)
	spr.animation = "idle"
	add_child(spr)
	if _mat_calm == null:
		var sh := load("res://shaders/sprite.gdshader")
		_mat_calm = ShaderMaterial.new()
		_mat_calm.shader = sh
		_mat_calm.set_shader_parameter("rim_color", Color(0.06, 0.05, 0.04, 0.0))
		_mat_angry = ShaderMaterial.new()
		_mat_angry.shader = sh
		_mat_angry.set_shader_parameter("rim_color", Color(0.85, 0.12, 0.12, 0.8))
		_mat_angry.set_shader_parameter("rim_px", 1.6)
	spr.material = _mat_calm
	modulate.a = 0.0

func top_y() -> float:
	var h: float = Res.creature_meta[type].height * Res.WSCALE[type]
	return position.y - h * (emerge if type == "worm" else 1.0) - lift - 10.0

## 한 프레임 생각하고 움직여요. 전투를 시작해야 하면 true
func think(dt: float, w) -> bool:
	if hp < t.hp:
		hp = minf(t.hp, hp + t.hp * 0.02 * dt)
	var to_p: Vector2 = w.ppos - position
	var d := maxf(1.0, to_p.length())
	var boss: bool = t.get("boss", false)
	if d > 1400 and not boss:
		mv = false
		visible = false
		return false
	visible = true
	born += dt
	modulate.a = minf(1.0, born / 0.7)
	var was := chase
	chase = t.aggro and w.grace <= 0 and w.pzone != 0 and d < (230.0 if boss else 170.0)
	if chase and not was:
		alert_t = 0.0
		if d < 400:
			Res.sfx("atk_" + type, -8.0)
	alert_t += dt
	# 토끼는 사람이 다가오면 도망쳐요
	flee = (type == "rabbit" and w.pzone != 0 and d < 130 and w.grace <= 0) or (flee and d < 240)
	var v := Vector2.ZERO
	var sp := 0.0
	if chase:
		v = to_p / d
		sp = t.spd * (0.0 if alert_t < 0.35 else 1.7)
	elif flee:
		v = -to_p / d
		sp = t.spd * 2.3
	else:
		wt -= dt
		if wt <= 0:
			wt = randf_range(1.5, 4.5)
			var a := randf() * TAU
			dir = Vector2.ZERO if randf() < 0.4 else Vector2(cos(a), sin(a))
		if dir != Vector2.ZERO:
			v = dir
			sp = t.spd
		var hd := home.distance_to(position)
		if hd > (90.0 if boss else 240.0):
			v = (home - position) / hd
			sp = t.spd
	var np := position + v * sp * dt
	mv = false
	if sp > 0 and Game.zone_at(np.x, np.y) != 0 and Game.walkable(np.x, np.y):
		position = np
		mv = true
	elif sp > 0 and not chase and not flee:
		wt = 0
	elif flee and sp > 0:
		dir = Vector2(-v.y, v.x)
		flee = false
	if absf(v.x) > 0.1:
		face = 1.0 if v.x > 0 else -1.0
	elif chase:
		face = 1.0 if to_p.x > 0 else -1.0
	var run := chase or flee
	if mv:
		anim += dt * TAU * sp / (Res.STRIDE[type] * Res.WSCALE[type] * (1.6 if run else 1.0))
	# 방향을 바꿀 땐 휙 뒤집히는 대신 살짝 눌렸다 돌아서요
	face_s += (face - face_s) * minf(1.0, dt * 9.0)
	if absf(face_s) < 0.15:
		face_s = -0.15 if face_s < 0 else 0.15
	if type == "worm":
		emerge = clampf(emerge + (2.0 if chase else -1.0) * dt, 0.0, 1.0)
	_pose(w.time)
	if mv and type in ["golem", "boar", "dragon", "yeti", "lizard"] and d < 700 and randf() < dt * 3.0:
		w.fx.dust(position + Vector2(randf_range(-8, 8), 0), 5.0 if type in ["dragon", "golem"] else 3.0)
	return chase and alert_t > 0.35 and d < 26.0 + t.size * 0.25

func _pose(time: float) -> void:
	lift = 0.0
	if Res.FLY.has(type):
		lift = Res.FLY[type] + sin(time * 3.0 + seed) * 4.0
	spr.position.y = -lift
	spr.scale = Vector2(_base * face_s, _base)
	spr.material = _mat_angry if chase else _mat_calm
	shadow.visible = type != "worm" or emerge > 0.3
	var anim_name := "idle"
	var f := 0
	if type == "worm" and emerge < 0.98 and (chase or emerge > 0.02):
		anim_name = "emerge"
		f = clampi(int(emerge * 6.0), 0, 5)
	elif type == "worm" and not chase and emerge <= 0.02:
		anim_name = "burrow"
		f = int(fposmod(anim, TAU) / TAU * 4.0) % 4
	elif mv:
		anim_name = "run" if (chase or flee) else "walk"
		f = int(fposmod(anim, TAU) / TAU * 8.0) % 8
	elif chase:
		anim_name = "ready"
		f = int(fposmod(time + seed, 3.0) / 3.0 * 8.0) % 8
	else:
		f = int(fposmod(time + seed, 3.0) / 3.0 * 8.0) % 8
	if spr.animation != anim_name:
		spr.animation = anim_name
	spr.frame = f
