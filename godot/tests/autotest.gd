extends Node
## 개발용 자동 점검: 화면을 돌며 스크린샷을 찍고, 봇이 전투를 해요

var out := "user://shots"
var step := 0
var t := 0.0
var world
var mon_type := "wolf"
var bot_hold = null
var shots := {}
var bot_miss := false

var runner := false

func _ready() -> void:
	if not runner:
		var r := Node.new()
		r.set_script(get_script())
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--mon="):
			mon_type = a.substr(6)
		if a == "--miss":
			bot_miss = true
	DirAccess.make_dir_recursive_absolute(out)
	Game.reset_game()
	Game.S.seen_help = true
	Game.S.gold = 5000
	Game.S.weapon = 3
	Game.refresh_stats()
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")

func shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("shot ", name)

func _process(dt: float) -> void:
	if not runner:
		return
	t += dt
	match step:
		0:
			if t > 1.0:
				shot("01_title")
				get_tree().change_scene_to_file("res://scenes/world.tscn")
				step = 1
				t = 0
		1:
			if t > 1.5:
				world = get_tree().current_scene
				shot("02_village")
				# 숲으로
				var p := _find_zone(2)
				world.ppos = p
				world.player.position = p
				world.cam.position = p
				step = 2
				t = 0
		2:
			if t > 1.0:
				world.grace = 99
				shot("03_forest")
				for z in [3, 4, 5, 6]:
					pass
				step = 3
				t = 0
		3:
			var zs := [3, 4, 5, 6]
			var i := int(t / 1.2)
			if i < zs.size():
				if fposmod(t, 1.2) < dt:
					var p := _find_zone(zs[i])
					world.ppos = p
					world.player.position = p
					world.cam.position = p
				if absf(fposmod(t, 1.2) - 1.0) < dt * 0.6:
					shot("04_zone%d" % zs[i])
			else:
				world.panels.open("shop")
				step = 4
				t = 0
		4:
			if t > 0.4 and not shots.has("shop"):
				shots.shop = true
				shot("05_shop")
				world.panels.close()
				world.panels.open("smith")
			elif t > 0.8 and not shots.has("smith"):
				shots.smith = true
				shot("06_smith")
				world.panels.close()
				world.panels.open("casino")
			elif t > 1.2 and not shots.has("casino"):
				shots.casino = true
				shot("07_casino")
				world.panels.casino_tab = "slot"
				world.panels.render()
			elif t > 1.6 and not shots.has("slot"):
				shots.slot = true
				shot("07b_slot")
				world.panels.close()
				world.panels.open("gacha")
				world.panels._pull(10)
			elif t > 4.2 and not shots.has("gacha"):
				shots.gacha = true
				shot("08_gacha")
				world.panels.close()
				world.panels.bag_tab = "charms"
				world.panels.open("bag")
			elif t > 4.6 and not shots.has("bag"):
				shots.bag = true
				shot("09_bag")
				world.panels.close()
				step = 5
				t = 0
		5:
			# 전투 시작
			var m = null
			for x in world.mons:
				if x.type == mon_type:
					m = x
					break
			print("start battle ", mon_type, " hp ", m.hp)
			world.ppos = m.position + Vector2(-40, 0)
			world.player.position = world.ppos
			world.start_battle(m)
			step = 6
			t = 0
		6:
			var b = world.battle
			if b == null:
				print("battle over, gold ", Game.S.gold, " lv ", Game.S.lv)
				shot("20_after")
				print("AUTOTEST DONE")
				get_tree().quit()
				return
			_bot(b)
			for q in b.sigs:
				if b.clock > q.t - 0.15 and b.clock < q.t - 0.05 and not shots.has("sig%s" % q.heavy):
					shots["sig%s" % q.heavy] = true
					shot("18_signal_%s" % ("heavy" if q.heavy else "normal"))
			if b.phase2 and not shots.has("rage") and b.clock > 0:
				shots.rage = true
				shots.rage_t = t
			if shots.has("rage_t") and t - shots.rage_t > 0.5 and not shots.has("rage2"):
				shots.rage2 = true
				shot("17_rage")
			for k in [0.5, 1.5, 3.2, 6.0, 9.0, 14.0, 20.0, 30.0, 45.0]:
				if t >= k and not shots.has(k):
					shots[k] = true
					shot("1%02d_battle_%04.1f" % [shots.size(), k])
			if b.over != null and b.result != null and not shots.has("res"):
				shots.res = true
				shot("19_result")
				print("result win=", b.over.win, " combo ", b.max_combo, " cnt ", b.cnt, " time ", t)
			if b.over != null and b.result != null and t > 0 and shots.has("res"):
				if not shots.has("closewait"):
					shots.closewait = t
				elif t - shots.closewait > 0.5:
					b.close_result()
			if b.over == null and int(t) % 5 == 0 and fposmod(t, 1.0) < dt:
				print("t=%.1f clock=%.2f hp=%d php=%d combo=%d phase2=%s notes=%d sigs=%d" % [t, b.clock, b.hp, Game.S.hp, b.combo, b.phase2, b.notes.size(), b.sigs.size()])
			if t > 300:
				print("TIMEOUT")
				get_tree().quit()

func _bot(b) -> void:
	if b.over != null or b.intro < 0.5:
		return
	var c: float = b.clock + 0.008
	if bot_hold != null:
		if c >= bot_hold.end:
			b.release("atk")
			bot_hold = null
		return
	for n in b.notes:
		if n.st != 0 or n.k == "trap":
			continue
		if c >= n.t and c - n.t < 0.05:
			if bot_miss and randf() < 0.5:
				continue
			b.press("atk")
			if n.k == "hold":
				bot_hold = n
			else:
				b.release("atk")
			break
	for q in b.sigs:
		if q.res == "" and c >= q.t and c - q.t < 0.05:
			if bot_miss and randf() < 0.5:
				continue
			b.press("def")

func _find_zone(z: int) -> Vector2:
	for k in 4000:
		var p := Vector2(randf_range(200, 7800), randf_range(200, 7800))
		if Game.zone_at(p.x, p.y) == z and Game.walkable(p.x, p.y):
			var r := p.distance_to(Game.center())
			if z <= 2 or r < 3200:
				return p
	return Game.center()
