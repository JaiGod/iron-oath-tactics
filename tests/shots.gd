extends Node
## Captures README screenshots (needs a display, e.g. xvfb-run). SHOTS=<dir>, PORTRAIT=1 for phone layout.
var main
var out := "user://"
var portrait := false

func _ready() -> void:
	out = OS.get_environment("SHOTS") if OS.get_environment("SHOTS") != "" else "user://"
	portrait = OS.get_environment("PORTRAIT") == "1"
	_run.call_deferred()

func f(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var w := 900 if not portrait else 420
	var j: Image = img.duplicate()
	j.resize(w, int(float(w) * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	j.save_jpg(out + "/" + name + ".jpg", 0.72)
	print("[shot] ", name)

func _run() -> void:
	if portrait:
		get_window().size = Vector2i(390, 844)
	else:
		get_window().size = Vector2i(1280, 720)
	Game.sound_on = false
	Game.delete_save()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await f(40)
	if portrait:
		Game.new_game("classic")
		_level_party(3)
		Game.mission = 3
		main.start_mission()
		await f(10)
		main.hud.speed = 20.0
		await get_tree().create_timer(0.4).timeout
		await f(20)
		var u = main.battle.team_units(0)[1]
		main.hud.on_tile(u.pos)
		await f(30)
		await snap("mobile")
		get_tree().quit()
		return
	await snap("title")
	Game.new_game("classic")
	_level_party(4)
	Game.mission = 2
	main.show_story(D.MISSIONS[2]["intro"], func(): pass)
	await f(60)
	await snap("story")
	Game.mission = 3
	main.start_mission()
	await f(10)
	var hud = main.hud
	hud.speed = 20.0
	await get_tree().create_timer(0.4).timeout
	await f(10)
	var b: Battle = main.battle
	# move the party forward a bit so the battlefield is busy
	for u in b.team_units(0):
		var mt := b.move_tiles(u)
		var best: Vector2i = u.pos
		for p in mt:
			if p.x > best.x and b.danger.get(p, 0) <= 1:
				best = p
		b.do_move(u, best)
		u.moved = false
		u.acted = false
	hud._sync_all()
	# enemies advance once
	for e in b.team_units(1):
		var plan := b.ai_plan(e)
		if plan["move"] != e.pos:
			b.do_move(e, plan["move"])
	for u in b.units:
		u.moved = false
		u.acted = false
	b.phase = 0
	hud._sync_all()
	await f(10)
	var sel = b.team_units(0)[0]
	for u in b.team_units(0):
		if u.cls == "lancer":
			sel = u
	hud.state = "idle"
	hud.on_tile(sel.pos)
	await f(40)
	await snap("battle")
	# forecast: pick the juiciest attack available after moving
	hud.cancel()
	var bestv := -1.0
	var pick := []
	for u in b.team_units(0):
		var aids: Array = [""] + u.abil
		for mt in b.move_tiles(u):
			for aid in aids:
				for tp in b.targets(u, mt, aid):
					var e = b.unit_at(tp)
					if e == null or e.team == 0:
						continue
					var fc := b.forecast(u, e, aid, mt)
					var v: float = float(fc["dmg"]) * fc["hit"] / 100.0 + (8.0 if aid != "" else 0.0)
					if v > bestv:
						bestv = v
						pick = [u, mt, aid, tp]
	var done := not pick.is_empty()
	if done:
		var u = pick[0]
		hud.on_tile(u.pos)
		b.do_move(u, pick[1])
		hud._sync_all()
		hud._open_menu()
		hud._choose(pick[2])
		hud._preview(pick[3])
	await f(40)
	await snap("forecast")
	if done:
		var ev := b.act(hud.sel, hud.cur_aid, hud.cur_target)
		hud.state = "busy"
		hud.speed = 1.0
		hud.play(ev)
		await get_tree().create_timer(0.62).timeout
		await snap("combat")
		await get_tree().create_timer(2.5).timeout
	main.show_camp()
	await f(20)
	await snap("camp")
	var camp = main.ui.get_child(main.ui.get_child_count() - 1)
	camp.tab = "shop"
	camp._rebuild()
	await f(10)
	await snap("shop")
	get_tree().quit()

func _level_party(lv: int) -> void:
	Game.roster.append(Game.make_unit("Quill", "mage", lv))
	Game.roster.append(Game.make_unit("Vex", "rogue", lv))
	for r in Game.roster:
		while int(r["lvl"]) < lv:
			Game.level_up(r)
