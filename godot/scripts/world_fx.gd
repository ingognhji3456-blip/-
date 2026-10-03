extends Node2D
## 필드 위에 그리는 것들: 체력바, 떠오르는 글자, 파편, 날씨 입자, 이동 표시

var w  # world.gd
var parts: Array = []   # {p, v, life, t, col, s}
var floats: Array = []  # {p, txt, col, size, t}
var amb: Array = []     # {k, p, v, r, life, t}
var marker := {}        # {p, t}

func burst(p: Vector2, col: Color, n := 8, sp := 120.0) -> void:
	for i in n:
		var a := randf() * TAU
		var v := randf_range(sp * 0.3, sp)
		parts.append({"p": p, "v": Vector2(cos(a) * v, sin(a) * v - 40), "life": randf_range(0.4, 0.8), "t": 0.0, "col": col, "s": randf_range(2, 4.5)})

func float_text(p: Vector2, txt: String, col := Color.WHITE, size := 16) -> void:
	floats.append({"p": p, "txt": txt, "col": col, "size": size, "t": 0.0})

func add_amb(o: Dictionary) -> void:
	if amb.size() < 260:
		o.t = 0.0
		if not o.has("v"):
			o.v = Vector2.ZERO
		amb.append(o)

func dust(p: Vector2, r := 3.0) -> void:
	add_amb({"k": "dust", "p": p, "v": Vector2(randf_range(-10, 10), randf_range(-12, -4)), "r": r, "life": 0.6})

func step(dt: float) -> void:
	for p in parts:
		p.t += dt
		p.p += p.v * dt
		p.v.y += 260 * dt
	parts = parts.filter(func(p): return p.t < p.life)
	for f in floats:
		f.t += dt
	floats = floats.filter(func(f): return f.t < 1.1)
	for a in amb:
		a.t += dt
		a.p += a.v * dt
	amb = amb.filter(func(a): return a.t < a.life)
	if marker:
		marker.t -= dt
		if marker.t <= 0:
			marker = {}
	queue_redraw()

func label(txt: String, p: Vector2, col: Color, size := 12) -> void:
	var f: Font = Res.font_xbold
	var pos := Vector2(p.x - 200, p.y + size * 0.36)
	draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 400, size, maxi(2, size / 5), Color(0, 0, 0, 0.75 * col.a))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, 400, size, col)

func hp_bar(p: Vector2, wd: float, frac: float, col: Color) -> void:
	draw_rect(Rect2(p.x - wd / 2 - 1, p.y - 1, wd + 2, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - wd / 2, p.y, wd * clampf(frac, 0, 1), 4), col)

func _draw() -> void:
	if w == null:
		return
	var cam: Rect2 = w.view_rect().grow(80)
	# 날씨·분위기 입자
	for a in amb:
		if not cam.has_point(a.p):
			continue
		var k: float = a.t / a.life
		var al := sin(k * PI)
		match a.k:
			"dust":
				draw_circle(a.p, a.r * (1 + k), Color(0.86, 0.8, 0.68, 0.35 * (1 - k)))
			"spark":
				var r: float = a.r * (0.5 + al * 0.5)
				draw_line(a.p - Vector2(r, 0), a.p + Vector2(r, 0), Color(1, 1, 1, 0.6 * al), 1.4)
				draw_line(a.p - Vector2(0, r * 0.6), a.p + Vector2(0, r * 0.6), Color(1, 1, 1, 0.5 * al), 1.2)
			"fly":
				draw_circle(a.p, 4.0, Color(0.85, 1.0, 0.5, 0.18 * al))
				draw_circle(a.p, a.r, Color(0.92, 1.0, 0.6, 0.9 * al))
			"snow":
				draw_circle(a.p, a.r, Color(1, 1, 1, 0.85 * al))
			"mist":
				draw_circle(a.p, a.r, Color(0.85, 0.92, 0.8, 0.06 * al))
			"smoke":
				draw_circle(a.p, a.r * (1 + k * 1.5), Color(0.75, 0.75, 0.75, 0.3 * (1 - k)))
	# 이동 표시
	if marker:
		var k2: float = 1.0 - marker.t / 0.6
		draw_set_transform(marker.p, 0, Vector2(1, 0.45))
		draw_arc(Vector2.ZERO, 6 + k2 * 14, 0, TAU, 28, Color(1, 1, 1, 0.8 * (1 - k2)), 2.0)
		draw_set_transform(Vector2.ZERO)
	# 자원 체력바
	for n in w.nodes_near(w.ppos, 400):
		var d: Dictionary = Game.D.nodeTypes[n.type]
		if not n.dead and n.hp < d.hp:
			hp_bar(n.pos + Vector2(0, -d.top - 6), 30, n.hp / d.hp, Color("ffd36b"))
	# 몬스터 표시
	for m in w.mons:
		if m.dead or not m.visible or not cam.has_point(m.position):
			continue
		var top: float = m.top_y()
		if m.hp < m.t.hp:
			hp_bar(Vector2(m.position.x, top), 34, m.hp / m.t.hp, Color("ff5d6c"))
		if m.chase:
			var pp := 1.0 + maxf(0.0, 0.3 - m.alert_t) * 2.0
			label("!", Vector2(m.position.x, top - 9), Color("ff5d6c"), int(18 * pp))
		elif m.flee:
			label("헉", Vector2(m.position.x + 10, top - 4), Color("bfe9ff"), 11)
		if m.t.get("boss", false):
			label(m.t.n, Vector2(m.position.x, top - 20), Color("ffb36b"), 13)
	# 건물 이름표
	for b in Game.D.world.buildings:
		var near: bool = w.ppos.distance_to(Vector2(b.x, b.y + 50)) < 140
		label(b.n, Vector2(b.x, b.y - 124), Color(1, 0.95, 0.8, 1.0 if near else 0.75), 15 if near else 13)
	# 정령
	if Game.ST.pet > 0:
		var sp: Vector2 = w.ppos + Vector2(cos(w.time * 2.0) * 26, -46 + sin(w.time * 3.0) * 6)
		draw_circle(sp, 10, Color(0.6, 1.0, 0.8, 0.2))
		draw_circle(sp, 4, Color(0.85, 1.0, 0.9, 0.95))
		if w.pet_beam:
			draw_line(sp, w.pet_beam.p, Color(0.7, 1.0, 0.85, 0.7 * w.pet_beam.t / 0.3), 2.0)
	# 귀환 중
	if w.P.home > 0:
		var k3: float = 1.0 - w.P.home / 2.0
		draw_arc(w.ppos + Vector2(0, -30), 26, -PI / 2, -PI / 2 + TAU * k3, 32, Color(0.75, 0.9, 1.0, 0.9), 3.0)
	# 파편
	for p in parts:
		draw_circle(p.p, p.s * (1.0 - p.t / p.life * 0.5), Color(p.col, 1.0 - p.t / p.life))
	for f in floats:
		var k4: float = f.t / 1.1
		var c: Color = f.col
		c.a = 1.0 if k4 < 0.6 else 1.0 - (k4 - 0.6) / 0.4
		label(f.txt, f.p + Vector2(0, -30 * sqrt(k4)), c, f.size)
