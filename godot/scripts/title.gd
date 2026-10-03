extends Control
## 첫 화면: 이어하기 / 새로 시작

var _t := 0.0
var _wolf: Sprite2D
var _hero: Sprite2D
var _bg: TextureRect

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = TextureRect.new()
	_bg.texture = Res.tex("res://assets/bg/battle_2.png")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_hero = Sprite2D.new()
	_hero.texture = Res.tex("res://assets/hero/hero_battle.png")
	_hero.region_enabled = true
	_hero.centered = false
	add_child(_hero)
	_wolf = Sprite2D.new()
	_wolf.texture = Res.tex("res://assets/creatures/wolf.png")
	_wolf.region_enabled = true
	_wolf.centered = false
	_wolf.flip_h = true
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sprite.gdshader")
	mat.set_shader_parameter("rim_color", Color(0.06, 0.05, 0.04, 0.5))
	_wolf.material = mat
	add_child(_wolf)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	v.position = Vector2(-220, -250)
	v.size = Vector2(440, 300)
	add_child(v)
	var title := preload("res://scripts/hud.gd").mk_label("떠돌이 사냥꾼", 64, Color("ffe9b0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 12)
	v.add_child(title)
	var sub := preload("res://scripts/hud.gd").mk_label("리듬에 맞춰 싸우는 사냥 모험", 20, Color(1, 1, 1, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	var has_save := FileAccess.file_exists(Game.SAVE_PATH)
	_btn(v, "이어하기" if has_save else "시작하기", Color("c0392b"), _start)
	if has_save:
		_btn(v, "새로 시작", Color("2a3350"), _new_game)
	var info := preload("res://scripts/hud.gd").mk_label("Lv %d · %s G · 처치 %d" % [Game.S.lv, Game.fmt(Game.S.gold), Game.S.kills] if has_save else "Enter 로 시작", 14, Color(1, 1, 1, 0.7))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)

func _btn(parent: Control, txt: String, col: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	preload("res://scripts/hud.gd").style_button(b, col, 22)
	b.custom_minimum_size = Vector2(280, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	parent.add_child(b)

var _confirm := false
func _new_game() -> void:
	if not _confirm:
		_confirm = true
		Res.sfx("miss")
		for c in get_children():
			if c is VBoxContainer:
				c.get_child(c.get_child_count() - 1).text = "정말 처음부터? 한 번 더 누르면 지워져요"
		return
	Game.reset_game()
	_start()

func _start() -> void:
	Res.sfx("start")
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("confirm"):
		_start()

func _process(dt: float) -> void:
	_t += dt
	var vs := get_viewport_rect().size
	var gy := vs.y * 0.86
	var hm: Dictionary = Res.hero_meta.battle
	var st: Dictionary = hm.states.idle
	_hero.region_rect = Res.cell(hm, int(st.start) + int(fposmod(_t, 0.8) / 0.8 * 8.0) % 8)
	_hero.offset = -Vector2(hm.ox, hm.oy)
	var pk := vs.y / 720.0 * 3.0
	_hero.scale = Vector2.ONE * pk / hm.ps
	_hero.position = Vector2(vs.x * 0.22, gy)
	var cm: Dictionary = Res.creature_meta.wolf
	_wolf.region_rect = Res.cell(cm, int(cm.states.ready.start) + int(fposmod(_t, 3.0) / 3.0 * 8.0) % 8)
	_wolf.offset = -Vector2(cm.ox, cm.oy)
	var mk := vs.y / 720.0 * 3.2
	_wolf.scale = Vector2.ONE * mk / cm.ps
	_wolf.position = Vector2(vs.x * 0.78, gy)
