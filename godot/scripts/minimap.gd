extends Control
## 오른쪽 위 작은 지도

var w
var _tex: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = Res.tex("res://assets/terrain/color.png")

func _draw() -> void:
	if w == null:
		return
	var s: float = size.x / w.WS
	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(0, 0, 0, 0.55))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var lair: Vector2 = Vector2(Game.D.world.lair.x, Game.D.world.lair.y) * s
	draw_circle(lair, 5, Color(1, 0.35, 0.15, 0.7))
	var bc := {"shop": Color("3d6fb8"), "smith": Color("a8482a"), "casino": Color("7a3cae"), "gacha": Color("b88a1e")}
	for b in Game.D.world.buildings:
		draw_rect(Rect2(Vector2(b.x, b.y) * s - Vector2(2, 2), Vector2(4, 4)), bc.get(b.id, Color.WHITE))
	for m in w.mons:
		if m.dead:
			continue
		var boss: bool = m.t.get("boss", false)
		var c := Color("ff3b1f") if boss else Color("ff8a95") if m.t.aggro else Color("ffe9a8")
		var r := 3.5 if boss else 1.0
		draw_rect(Rect2(m.position * s - Vector2(r, r), Vector2(r * 2, r * 2)), c)
	draw_circle(w.ppos * s, 4.5, Color.BLACK)
	draw_circle(w.ppos * s, 3.5, Color.WHITE)
	var vr: Rect2 = w.view_rect()
	draw_rect(Rect2(vr.position * s, vr.size * s), Color(1, 1, 1, 0.6), false, 1.0)
