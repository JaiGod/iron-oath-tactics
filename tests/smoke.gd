extends Node
## Headless smoke test: boots the real UI, plays battles through the HUD controller,
## exercises camp (shop, equip, promote, hire), save/load, permadeath and every mission's map.
var fails := 0
var main

func check(c: bool, msg: String) -> void:
	print(("  ok   " if c else "  FAIL ") + msg)
	if not c:
		fails += 1

func f(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	Game.delete_save()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await f(5)
	check(main.screen == "title", "boots to title")
	check(main.board != null, "title backdrop board drawn")
	main.show_howto()
	await f()
	main.show_new()
	await f()
	main._begin_campaign("classic")
	await f()
	check(main.screen == "story", "intro story shown")
	check(Game.roster.size() == 4 and Game.get_lord() != null, "4 starting heroes with a lord")
	for i in 10:
		main._story_next()
		main._story_next()
		if main.screen != "story":
			break
	await f(3)
	check(main.screen == "battle" and main.hud != null, "mission 1 battle starts")
	var hud = main.hud
	hud.speed = 50.0
	await get_tree().create_timer(0.3).timeout
	var b: Battle = main.battle
	# selection state machine through the real handlers
	var u = b.team_units(0)[0]
	hud.state = "idle"
	hud.on_tile(u.pos)
	check(hud.state == "moving" and not main.board.move_set.is_empty(), "tap selects unit and shows move tiles")
	var dest: Vector2i = main.board.move_set[0]
	for p in main.board.move_set:
		if p != u.pos:
			dest = p
	await hud.on_tile(dest)
	check(hud.state == "menu" and u.pos == dest, "tap moves unit and opens action menu")
	hud.cancel()
	check(hud.state == "moving" and u.pos == hud.undo_pos, "undo restores position")
	hud.cancel()
	# auto-play the battle using AI for the player side through HUD end_turn
	var won := await play_battle(hud, b)
	for attempt in 4:
		if won == "win":
			break
		await f(3)
		main.start_mission()
		await f(3)
		main.hud.speed = 50.0
		won = await play_battle(main.hud, main.battle)
	check(won == "win", "mission 1 won via HUD (result=%s)" % won)
	await f(5)
	check(Game.mission == 1, "mission advanced to 2")
	var q := false
	for r in Game.roster:
		if r["name"] == "Quill":
			q = true
	check(q, "recruit Quill joined (roster %d)" % Game.roster.size())
	check(Game.has_save(), "game saved to user://")
	# camp
	main.show_camp()
	await f(3)
	check(main.screen == "camp", "camp opens")
	var camp = main.ui.get_child(main.ui.get_child_count() - 1)
	for t in ["shop", "tavern", "roster"]:
		camp.tab = t
		camp._rebuild()
		await f()
	Game.gold = 9000
	check(Game.buy("steel_sword"), "buy steel sword")
	var lord: Dictionary = Game.get_lord()
	check(Game.equip(lord, "steel_sword") and lord["weapon"] == "steel_sword", "equip weapon")
	check(not Game.equip(lord, "javelin"), "cannot equip wrong weapon type")
	check(Game.buy("iron_buckler") and Game.equip(lord, "iron_buckler"), "equip gear")
	check(Game.hire("mage"), "hire mercenary")
	while int(lord["lvl"]) < 8:
		Game.level_up(lord)
	Game.buy("oath_crest")
	check(Game.promote(lord) and lord["promoted"], "promote lord to Paladin")
	camp._rebuild()
	await f()
	# save/load roundtrip
	Game.save_game()
	var g0: int = Game.gold
	Game.gold = 0
	check(Game.load_game() and Game.gold == g0 and Game.get_lord()["promoted"], "save/load roundtrip")
	# permadeath
	var before: int = Game.roster.size()
	var victim: String = Game.roster[1]["name"]
	Game.mission = 1
	var notes := Game.finish_mission({"fallen": [victim], "turns": 5, "kills": 3})
	check(Game.roster.size() == before and notes.size() > 0, "classic permadeath removes fallen (and recruit joins)")
	var still := false
	for r in Game.roster:
		if r["name"] == victim:
			still = true
	check(not still, "fallen unit gone in classic")
	# every mission map: valid spawns, abilities, AI turn
	for mi in D.MISSIONS.size():
		var bb := Battle.new()
		var ros: Array = []
		for c in ["knight", "archer", "healer", "lancer", "engineer", "beastmaster"]:
			var r := Game.make_unit(c, c, 9, c == "knight")
			r["promoted"] = true
			ros.append(r)
		bb.setup(mi, ros)
		var ok := true
		for x in bb.units:
			if not bb.passable_t(x.pos):
				ok = false
		check(ok and bb.team_units(1).size() >= 4, "mission %d map + %d foes valid" % [mi + 1, bb.team_units(1).size()])
		# use every ability once where possible
		for x in bb.team_units(0):
			for aid in x.abil:
				var tl := bb.targets(x, x.pos, aid)
				if not tl.is_empty() and not x.acted:
					bb.act(x, aid, tl[0])
		bb.start_phase(1)
		for e in bb.team_units(1):
			if bb.result == "":
				bb.ai_turn(e)
		bb.start_phase(0)
	# play the next mission through the HUD as well (defend)
	Game.mission = 1
	main.start_mission()
	await f(3)
	main.hud.speed = 50.0
	var r2 := await play_battle(main.hud, main.battle)
	check(r2 == "win" or r2 == "lose", "mission 2 (defend) resolves: %s" % r2)
	await f(3)
	main.show_ending()
	await f(2)
	main.show_title()
	await f(2)
	Game.delete_save()
	print("SMOKE OK" if fails == 0 else "SMOKE FAILED (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func play_battle(hud, b: Battle) -> String:
	var res := [""]
	hud.finished.connect(func(r, _d): res[0] = r, CONNECT_ONE_SHOT)
	for t in 40:
		while hud.state == "busy":
			await f()
		if res[0] != "" or hud.state == "over":
			break
		for u in b.team_units(0):
			if b.result != "" or u.acted:
				continue
			var ev := b.ai_turn(u)
			await hud.play(ev)
			hud._sync_all()
		if await hud._check_end():
			await f(2)
			break
		hud.state = "idle"
		await hud.end_turn()
		await f(2)
		if res[0] != "":
			break
	for i in 200:
		if res[0] != "":
			break
		await f()
	return res[0] if res[0] != "" else b.result
