extends CanvasLayer
## 화면 위 정보: 골드·체력·경험치, 지역 이름, 버튼, 미니맵, 알림

var w
var stat: PanelContainer
var gold_l: Label
var hp_bar: ProgressBar
var hp_l: Label
var xp_bar: ProgressBar
var lv_l: Label
var zone_l: Label
var hint_l: Label
var btns: HBoxContainer
var pot_b: Button
var snd_b: Button
var mini: Control
var toasts: VBoxContainer
var _key := ""

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# 왼쪽 위 상태판
	stat = PanelContainer.new()
	stat.add_theme_stylebox_override("panel", box(Color(0.04, 0.05, 0.09, 0.72), 12))
	stat.position = Vector2(12, 12)
	stat.custom_minimum_size = Vector2(250, 0)
	root.add_child(stat)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	stat.add_child(v)
	gold_l = mk_label("0", 20, Color("ffd24a"))
	v.add_child(gold_l)
	hp_bar = mk_bar(Color("3fc46f"))
	v.add_child(hp_bar)
	hp_l = mk_label("", 12, Color.WHITE)
	hp_l.position = Vector2(0, 0)
	hp_bar.add_child(hp_l)
	hp_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_bar = mk_bar(Color("6aa8ff"))
	xp_bar.custom_minimum_size.y = 7
	v.add_child(xp_bar)
	lv_l = mk_label("", 12, Color("aeb8c8"))
	v.add_child(lv_l)
	# 지역 이름
	zone_l = mk_label("", 18, Color.WHITE)
	zone_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	zone_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_l.position = Vector2(-200, 14)
	zone_l.size = Vector2(400, 30)
	root.add_child(zone_l)
	hint_l = mk_label("", 13, Color(1, 1, 1, 0.75))
	hint_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_l.position = Vector2(-420, -86)
	hint_l.size = Vector2(840, 24)
	root.add_child(hint_l)
	# 오른쪽 아래 버튼
	btns = HBoxContainer.new()
	btns.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btns.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btns.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btns.position = Vector2(-12, -12)
	btns.add_theme_constant_override("separation", 8)
	root.add_child(btns)
	pot_b = add_btn("물약 (Q)", func(): w.use_potion())
	add_btn("가방 (I)", func(): w.panels.open("bag"))
	add_btn("귀환 (H)", func(): w.go_home())
	snd_b = add_btn("소리 켬", func():
		Game.sound_on = not Game.sound_on
		_key = "")
	add_btn("도움말", func(): w.panels.open("help"))
	# 미니맵
	mini = preload("res://scripts/minimap.gd").new()
	mini.w = w
	mini.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mini.position = Vector2(-12 - 150, 12)
	mini.size = Vector2(150, 150)
	root.add_child(mini)
	# 알림
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-260, 54)
	toasts.size = Vector2(520, 10)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(toasts)

static func box(c: Color, r := 10, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(2)
	return s

static func mk_label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", Res.font_xbold)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func mk_bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(6)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func style_button(b: Button, col := Color(0.12, 0.14, 0.22, 0.9), size := 15) -> void:
	b.add_theme_stylebox_override("normal", box(col, 10))
	b.add_theme_stylebox_override("hover", box(col.lightened(0.15), 10))
	b.add_theme_stylebox_override("pressed", box(col.darkened(0.2), 10))
	b.add_theme_stylebox_override("disabled", box(Color(col, 0.4), 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", Res.font_xbold)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))

func add_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	style_button(b)
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	btns.add_child(b)
	return b

func set_battle(on: bool) -> void:
	zone_l.visible = not on
	hint_l.visible = not on
	btns.visible = not on
	mini.visible = not on
	toasts.visible = not on
	layer = 11 if on else 5  # 전투 중에도 골드·체력판은 위에 보여요
	_key = ""

func gold_pos() -> Vector2:
	return gold_l.global_position + Vector2(14, 12)

func toast(msg: String, kind := "") -> void:
	var p := PanelContainer.new()
	var col := Color(0.06, 0.07, 0.12, 0.88)
	var border := Color(1, 1, 1, 0.15)
	match kind:
		"gold": border = Color("ffcf4a")
		"good": border = Color("5fdc8a")
		"bad": border = Color("ff6b78")
	p.add_theme_stylebox_override("panel", box(col, 10, border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := mk_label(msg, 15, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)

func refresh() -> void:
	var S := Game.S
	var key := "%d|%d|%d|%d|%d|%d|%s|%d" % [S.gold, ceili(S.hp), Game.max_hp(), S.xp, S.lv, S.potions, Game.sound_on, w.pzone]
	mini.queue_redraw()
	if key == _key:
		return
	_key = key
	gold_l.text = "%s G" % Game.fmt(S.gold)
	hp_bar.max_value = Game.max_hp()
	hp_bar.value = clampf(S.hp, 0, Game.max_hp())
	hp_l.text = "체력 %d / %d" % [ceili(S.hp), Game.max_hp()]
	xp_bar.max_value = Game.xp_need(S.lv)
	xp_bar.value = S.xp
	lv_l.text = "Lv %d · 경험치 %s / %s" % [S.lv, Game.fmt(S.xp), Game.fmt(Game.xp_need(S.lv))]
	pot_b.text = "물약 %d (Q)" % S.potions
	snd_b.text = "소리 켬" if Game.sound_on else "소리 끔"
	zone_l.text = Game.zone_name(w.pzone)
	if w.pzone == 0:
		hint_l.text = "건물 앞으로 걸어가면 들어가요 · 마을에서는 체력이 차올라요"
	else:
		hint_l.text = "WASD/클릭 이동 · Shift 달리기 · 자원·몬스터를 클릭하거나 가까이서 Space · Q 물약 · I 가방"
