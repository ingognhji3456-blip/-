extends Node
## 구워 둔 에셋(스프라이트 시트·소리)을 불러와 쓰기 좋게 만들어요

var creature_meta: Dictionary
var hero_meta: Dictionary
var props_meta: Dictionary
var font_bold: Font
var font_xbold: Font
var _frames := {}
var _tex := {}
var _snd := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

const WSCALE := {"slime": 1.05, "rabbit": 1.0, "wolf": 1.0, "boar": 1.1, "bat": 1.0, "golem": 1.05, "dragon": 1.0, "wisp": 1.0, "yeti": 1.05, "scorp": 1.05, "worm": 1.0, "toad": 1.15, "lizard": 1.0}
const STRIDE := {"slime": 26, "rabbit": 30, "wolf": 30, "boar": 22, "bat": 40, "golem": 24, "dragon": 44, "wisp": 40, "yeti": 28, "scorp": 14, "worm": 40, "toad": 30, "lizard": 32}
const FLY := {"bat": 26.0, "wisp": 20.0}
const SHW := {"slime": 15, "rabbit": 12, "wolf": 24, "boar": 24, "bat": 8, "golem": 22, "dragon": 60, "wisp": 10, "yeti": 22, "scorp": 26, "worm": 24, "toad": 18, "lizard": 16}
const MAT := {"slime": "goo", "golem": "stone", "wisp": "ice", "worm": "sand", "scorp": "chitin", "bat": "fur", "dragon": "scale", "lizard": "scale", "toad": "goo", "rabbit": "fur", "wolf": "fur", "boar": "fur", "yeti": "fur"}
const MAT_COL := {"goo": ["9fe08a", "d8ffd0", "5fbf5a"], "stone": ["8a8478", "c2bbad", "5a554c"], "ice": ["ffffff", "bfe9ff", "7ec8f0"], "sand": ["d8b67a", "b08d5a", "efd8a8"], "chitin": ["5a3818", "a8743a", "2a180a"], "fur": ["d8d0c2", "8a8276", "5a544b"], "scale": ["c8452f", "e0a050", "5a1610"]}

func _ready() -> void:
	creature_meta = _json("res://assets/creatures/creatures.json")
	hero_meta = _json("res://assets/hero/hero.json")
	props_meta = _json("res://assets/props/props.json")
	font_bold = load("res://assets/fonts/NanumGothic-Bold.ttf")
	font_xbold = load("res://assets/fonts/NanumGothic-ExtraBold.ttf")
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]

func cell(meta: Dictionary, idx: int) -> Rect2:
	var cols := int(meta.cols)
	return Rect2((idx % cols) * meta.fw, int(idx / cols) * meta.fh, meta.fw, meta.fh)

func _frames_from(sheet: Texture2D, meta: Dictionary, fps: Dictionary, loops: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for st in meta.states:
		var s: Dictionary = meta.states[st]
		sf.add_animation(st)
		sf.set_animation_speed(st, fps.get(st, 8))
		sf.set_animation_loop(st, loops.get(st, true))
		for i in int(s.count):
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = cell(meta, int(s.start) + i)
			sf.add_frame(st, at)
	return sf

func creature_frames(type: String) -> SpriteFrames:
	if not _frames.has(type):
		_frames[type] = _frames_from(tex("res://assets/creatures/%s.png" % type), creature_meta[type],
			{"idle": 5, "walk": 10, "run": 14, "ready": 8, "burrow": 6, "emerge": 8, "dead": 10},
			{"wind": false, "lunge": false, "hurt": false, "dead": false, "emerge": false})
	return _frames[type]

func hero_world_frames() -> SpriteFrames:
	if not _frames.has("hero"):
		_frames["hero"] = _frames_from(tex("res://assets/hero/hero_world.png"), hero_meta.world,
			{"down_idle": 3, "up_idle": 3, "side_idle": 3, "down_walk": 12, "up_walk": 12, "side_walk": 12, "side_swing": 24},
			{"side_swing": false})
	return _frames["hero"]

func prop_sprite(key: String) -> Sprite2D:
	var m: Dictionary = props_meta[key]
	var s := Sprite2D.new()
	s.texture = tex("res://assets/props/%s.png" % key)
	s.centered = false
	var sc := 1.0 / float(m.scale)
	s.scale = Vector2(sc, sc)
	s.offset = -Vector2(m.ax, m.ay) * float(m.scale)
	return s

func sfx(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not Game.sound_on:
		return
	if not _snd.has(name):
		var path := "res://assets/audio/sfx/%s.ogg" % name
		if not ResourceLoader.exists(path):
			return
		_snd[name] = load(path)
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _snd[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

## 동그란 그림자 텍스처 (한 번만 만들어 써요)
var _shadow: Texture2D
func shadow_tex() -> Texture2D:
	if _shadow == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.42))
		g.set_color(1, Color(0, 0, 0, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_shadow = t
	return _shadow

func make_shadow(w: float, h: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = shadow_tex()
	s.scale = Vector2(w * 2.0 / 64.0, h * 2.0 / 64.0)
	s.z_index = -1
	return s

func hexc(h: String) -> Color:
	return Color.html(h)
