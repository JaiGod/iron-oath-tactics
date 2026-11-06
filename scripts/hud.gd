extends Control
## Battle controller + HUD: turns, selection state machine, action menu, forecasts, enemy phase.

signal finished(result: String, data: Dictionary)

var b: Battle
var board
var state := "idle"      # idle | moving | menu | target | confirm | busy | over
var sel = null
var undo_pos := Vector2i.ZERO
var undo_face := 0
var cur_aid := ""
var cur_target := Vector2i(-1, -1)
var top: PanelContainer
var bottom: PanelContainer
var bottom_box: BoxContainer
var obj_lbl: Label
var name_lbl: Label
var turn_lbl: Label
var end_btn: Button
var info: RichTextLabel
var acts: HFlowContainer
var banner: Label
var pause_layer: Control = null
var speed := 1.0
var _last_fit := Rect2()
var portrait := false
var auto_test := false

func start(battle: Battle, board_node) -> void:
	b = battle
	board = board_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	board.setup(b)
	board.interactive = true
	board.tile_tapped.connect(on_tile)
	board.tile_hovered.connect(on_hover)
	for u in b.units:
		if u.team == 0:
			b.face_nearest_enemy(u)
	_refresh()
	_show_hint()
	await _banner("Mission %d: %s" % [b.mi + 1, b.m["name"]], UI.GOLD)
	await _banner("Player Phase", UI.BLUE)

func _build() -> void:
	top = PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6; top.offset_right = -6; top.offset_top = 6
	add_child(top)
	var th := UI.hbox(8)
	top.add_child(th)
	th.add_child(UI.btn("II", _pause, 44))
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl = UI.lbl("", 18, UI.GOLD)
	obj_lbl = UI.lbl("", 15, UI.INK)
	tv.add_child(name_lbl)
	tv.add_child(obj_lbl)
	th.add_child(tv)
	turn_lbl = UI.lbl("", 18, UI.INK)
	turn_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	turn_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(turn_lbl)
	th.add_child(UI.btn("-", func(): board.zoom_by(1.0 / 1.2), 40))
	th.add_child(UI.btn("+", func(): board.zoom_by(1.2), 40))
	end_btn = UI.btn("End Turn", end_turn, 110)
	th.add_child(end_btn)
	bottom = PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 6; bottom.offset_right = -6; bottom.offset_bottom = -6
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	bottom_box = BoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 10)
	bottom.add_child(bottom_box)
	info = UI.rich("", 16)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(300, 0)
	bottom_box.add_child(info)
	acts = HFlowContainer.new()
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	acts.alignment = FlowContainer.ALIGNMENT_END
	bottom_box.add_child(acts)
	banner = UI.lbl("", 44, UI.GOLD, 10)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.custom_minimum_size = Vector2(500, 0)
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)

func _process(_d: float) -> void:
	if b == null:
		return
	var vs := get_viewport_rect().size
	var p := vs.y > vs.x
	if p != portrait:
		portrait = p
		bottom_box.vertical = portrait
		info.custom_minimum_size.x = 0 if portrait else 300
	var r := Rect2(Vector2(0, top.position.y + top.size.y), Vector2(vs.x, bottom.position.y - top.position.y - top.size.y))
	if r.size.y > 80 and r != _last_fit:
		_last_fit = r
		board.fit(r.grow(-6))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ESCAPE:
		if state in ["moving", "menu", "target", "confirm"]:
			cancel()
		else:
			_pause()
	elif k == KEY_E and state == "idle":
		end_turn()

# ---------------------------------------------------------------- info panels
func _unit_bb(u) -> String:
	var c: Dictionary = D.CLASSES[u.cls]
	var cn: String = c["promo"] if u.promoted else c["name"]
	var col := "7fb2ff" if u.team == 0 else "ff8a7a"
	if u.npc:
		col = "7fe08a"
	var w: Dictionary = b.wpn(u)
	var s := "[b][color=#%s]%s[/color][/b]  Lv %d %s%s   HP [b]%d/%d[/b]" % [col, u.name, u.lvl, cn, " (Boss)" if u.boss else "", u.hp, u.mhp()]
	if u.team == 0 and u.ref != null:
		s += "   XP %d" % u.xp
	s += "\n[color=#b3a58c]STR[/color] %d [color=#b3a58c]MAG[/color] %d [color=#b3a58c]SKL[/color] %d [color=#b3a58c]SPD[/color] %d [color=#b3a58c]DEF[/color] %d [color=#b3a58c]RES[/color] %d [color=#b3a58c]MOV[/color] %d" % [b.stat(u, "str"), b.stat(u, "mag"), b.stat(u, "skl"), b.stat(u, "spd"), b.stat(u, "def"), b.stat(u, "res"), b.stat(u, "mov")]
	if w["type"] != "none":
		s += "\n%s [color=#b3a58c](%s, Mt %d, Hit %d, Rng %d-%d)[/color]" % [w["name"], w["type"], w["mt"], w["hit"], w["r"][0], w["r"][1]]
	if not u.status.is_empty():
		s += "  [color=#c9a0ff]" + ", ".join(u.status.keys()) + "[/color]"
	return s

func _tile_bb(p: Vector2i) -> String:
	var ti := b.tinfo(p)
	var s := "[color=#e0b552]%s[/color] · height %d" % [ti["name"], b.h(p)]
	if int(ti["def"]) != 0 or int(ti["avo"]) != 0:
		s += " · DEF %+d AVO %+d" % [ti["def"], ti["avo"]]
	if ti.get("cover", false):
		s += " · cover"
	if int(ti.get("heal", 0)) > 0:
		s += " · heals %d%%" % ti["heal"]
	if not ti["pass"]:
		s += " · impassable"
	return s

func _show_hint() -> void:
	info.text = "[color=#e0b552]Your turn.[/color] Tap a blue unit to select it, tap a blue tile to move, then choose an action.\n[color=#b3a58c]Strike from behind (+50%) or the side (+20%). High ground hits harder. Swords > Axes > Lances > Swords.[/color]"
	_set_actions([])

func _set_actions(list: Array) -> void:
	for c in acts.get_children():
		c.queue_free()
	for it in list:
		var bt := UI.btn(it[0], it[1], 96)
		if it.size() > 2:
			bt.disabled = not it[2]
		acts.add_child(bt)

func _refresh() -> void:
	name_lbl.text = "M%d · %s" % [b.mi + 1, b.m["name"]]
	obj_lbl.text = b.objective_text()
	turn_lbl.text = "Turn %d" % b.turn
	end_btn.disabled = state != "idle"
	board.selected_id = sel.id if sel != null else -1

func _clear_marks() -> void:
	board.move_set = []
	board.atk_set = []
	board.abil_set = []
	board.area_set = []
	board.path_set = []

# ---------------------------------------------------------------- input state machine
func on_hover(p: Vector2i) -> void:
	if state == "busy" or state == "over":
		return
	if state == "moving" and sel != null and board.move_set.has(p):
		board.path_set = b.path_to(sel, p)
	if state == "idle":
		var u = b.unit_at(p)
		info.text = (_unit_bb(u) + "\n" if u != null else "") + _tile_bb(p)

func on_tile(p: Vector2i) -> void:
	if state == "busy" or state == "over" or b.phase != 0:
		return
	var u = b.unit_at(p)
	match state:
		"idle":
			if u != null and u.team == 0 and not u.acted:
				_select(u)
			elif u != null:
				_show_threat(u)
			else:
				_clear_marks()
				info.text = _tile_bb(p)
		"moving":
			if p == sel.pos:
				_open_menu()
			elif board.move_set.has(p):
				await _move_selected(p)
			elif u != null and u.team == 0 and not u.acted:
				_select(u)
			else:
				cancel()
		"menu":
			if u != null and u.team == 0 and not u.acted and not sel.moved and u != sel:
				_select(u)
		"target", "confirm":
			if board.atk_set.has(p) or board.abil_set.has(p):
				if state == "confirm" and p == cur_target:
					await _execute()
				else:
					_preview(p)
			else:
				_open_menu()

func _show_threat(u) -> void:
	_clear_marks()
	sel = null
	var tiles: Array = b.move_tiles(u) if not u.acted or u.team != 0 else [u.pos]
	board.move_set = tiles
	var rr := b.ranges(u, "")
	var reachable := {}
	if b.can_attack(u):
		for s in tiles:
			for y in range(-rr[1], rr[1] + 1):
				for x in range(-rr[1], rr[1] + 1):
					var q: Vector2i = s + Vector2i(x, y)
					var d: int = abs(x) + abs(y)
					if b.inb(q) and d >= rr[0] and d <= rr[1] and not tiles.has(q):
						reachable[q] = true
	board.atk_set = reachable.keys()
	info.text = _unit_bb(u) + "\n" + _tile_bb(u.pos)
	_refresh()

func _select(u) -> void:
	sel = u
	state = "moving"
	undo_pos = u.pos
	undo_face = u.facing
	_clear_marks()
	board.move_set = b.move_tiles(u)
	var at := {}
	if b.can_attack(u):
		for s in board.move_set:
			for tp in b.targets(u, s, ""):
				at[tp] = true
	board.atk_set = at.keys()
	info.text = _unit_bb(u) + "\n" + _tile_bb(u.pos)
	_set_actions([["Act here", _open_menu], ["Cancel", cancel]])
	Sfx.play("select")
	_refresh()

func _move_selected(p: Vector2i) -> void:
	state = "busy"
	_clear_marks()
	var path := b.do_move(sel, p)
	await _anim_path(sel.id, path)
	_open_menu()

func _open_menu() -> void:
	if sel == null:
		state = "idle"
		return
	state = "menu"
	sel.moved = true
	_clear_marks()
	cur_aid = ""
	var list: Array = []
	if b.can_attack(sel):
		list.append(["Attack", func(): _choose(""), not b.targets(sel, sel.pos, "").is_empty()])
	for aid in sel.abil:
		var a: Dictionary = D.ABIL[aid]
		var cd: int = int(sel.cds.get(aid, 0))
		var label: String = a["name"] + ((" (%d)" % cd) if cd > 0 else "")
		list.append([label, func(): _choose(aid), b.ability_ready(sel, aid) and not b.targets(sel, sel.pos, aid).is_empty()])
	list.append(["Wait", _wait])
	list.append(["Undo", cancel])
	_set_actions(list)
	var tip := ""
	for aid in sel.abil:
		tip += "\n[color=#c9a0ff]%s[/color]: %s" % [D.ABIL[aid]["name"], D.ABIL[aid]["desc"]]
	info.text = _unit_bb(sel) + "\n" + _tile_bb(sel.pos) + tip
	_refresh()

func _choose(aid: String) -> void:
	cur_aid = aid
	state = "target"
	_clear_marks()
	var tl := b.targets(sel, sel.pos, aid)
	var a := b.abil_info(aid)
	var kind: String = a.get("kind", "attack")
	if kind == "attack":
		board.atk_set = tl
	else:
		board.abil_set = tl
	info.text = "[color=#e0b552]%s[/color] — %s\nTap a highlighted tile to preview, tap again (or Confirm) to execute." % [a.get("name", "Attack"), a.get("desc", "Strike with your weapon.")]
	_set_actions([["Back", _open_menu]])
	if tl.size() == 1 and (kind != "attack" or int(a.get("r", [1, 1])[1]) == 0):
		_preview(tl[0])

func _preview(p: Vector2i) -> void:
	cur_target = p
	state = "confirm"
	board.cursor = p
	var a := b.abil_info(cur_aid)
	var kind: String = a.get("kind", "attack")
	board.area_set = []
	var s := ""
	if kind == "attack":
		var list: Array = []
		if int(a.get("aoe", 0)) > 0:
			board.area_set = b.area(cur_aid, p)
			for q in board.area_set:
				var e = b.unit_at(q)
				if e != null and e.team != sel.team:
					list.append(e)
		else:
			var e = b.unit_at(p)
			if e != null:
				list.append(e)
		var apos: Vector2i = sel.pos
		if a.get("step", false) and list.size() > 0:
			var bp: Vector2i = list[0].pos - Battle.DIRS[list[0].facing]
			apos = bp
		elif a.get("line", false):
			apos = p - Vector2i(sign(p.x - sel.pos.x), sign(p.y - sel.pos.y))
		for e in list:
			var f := b.forecast(sel, e, cur_aid, apos)
			var kill: bool = int(f["dmg"]) * (2 if f["double"] else 1) >= e.hp
			s += "[b]%s[/b] » [color=#ff8a7a]%s[/color] (HP %d)%s\n" % [sel.name, e.name, e.hp, "  [color=#ffd24a]KO![/color]" if kill else ""]
			s += "  DMG [b]%d[/b]%s · HIT [b]%d%%[/b] · CRIT %d%%" % [f["dmg"], " x2" if f["double"] else "", f["hit"], f["crit"]]
			if f["counter"] != null:
				var c: Dictionary = f["counter"]
				s += "\n  Counter: DMG %d%s · HIT %d%% · CRIT %d%%" % [c["dmg"], " x2" if c["double"] else "", c["hit"], c["crit"]]
			else:
				s += "\n  [color=#6fd07a]No counterattack[/color]"
			if not f["notes"].is_empty():
				s += "\n  [color=#c9a0ff]" + ", ".join(f["notes"]) + "[/color]"
			s += "\n"
	elif kind == "heal":
		if int(a.get("aoe", 0)) > 0:
			board.area_set = b.area("sanctuary", sel.pos)
		var amt: int = int(a.get("amt", 8)) + b.stat(sel, "mag") + int(b.wpn(sel).get("heal", 0))
		s = "[color=#6fd07a]%s[/color]: restore up to %d HP." % [a["name"], amt]
	else:
		if int(a.get("aoe", 0)) > 0:
			board.area_set = b.area(cur_aid, sel.pos)
		s = "[color=#c9a0ff]%s[/color]: %s" % [a["name"], a["desc"]]
	info.text = s.strip_edges()
	_set_actions([["Confirm", _execute], ["Back", func(): _choose(cur_aid)]])

func _execute() -> void:
	if state != "confirm" or sel == null:
		return
	state = "busy"
	_set_actions([])
	_clear_marks()
	var ev := b.act(sel, cur_aid, cur_target)
	await play(ev)
	_after_action()

func _wait() -> void:
	b.do_wait(sel)
	_after_action()

func cancel() -> void:
	if state == "moving":
		sel = null
		state = "idle"
		_clear_marks()
		_show_hint()
	elif state == "menu":
		if sel.pos != undo_pos and unit_free(undo_pos):
			sel.pos = undo_pos
			board.sync_unit(sel)
		sel.facing = undo_face
		sel.moved = false
		_select(sel)
	elif state == "target" or state == "confirm":
		_open_menu()
	_refresh()

func unit_free(p: Vector2i) -> bool:
	var o = b.unit_at(p)
	return o == null or o == sel

func _after_action() -> void:
	sel = null
	_clear_marks()
	_sync_all()
	if await _check_end():
		return
	state = "idle"
	_show_hint()
	_refresh()
	if b.phase_done(0):
		await get_tree().create_timer(0.35 / speed).timeout
		end_turn()

# ---------------------------------------------------------------- enemy phase
func end_turn() -> void:
	if state != "idle":
		return
	state = "busy"
	sel = null
	_clear_marks()
	_set_actions([])
	_refresh()
	for u in b.team_units(0):
		if not u.acted:
			b.do_wait(u)
	await _banner("Enemy Phase", UI.RED)
	await play(b.start_phase(1))
	if await _check_end():
		return
	var foes: Array = b.team_units(1)
	foes.sort_custom(func(x, y): return b.wpn(x)["r"][1] > b.wpn(y)["r"][1])
	for u in foes:
		if not u.alive or b.result != "":
			continue
		var plan := b.ai_plan(u)
		info.text = _unit_bb(u)
		if plan["move"] != u.pos:
			var path := b.do_move(u, plan["move"])
			await _anim_path(u.id, path)
		if plan["target"] != null:
			board.cursor = plan["target"]
			await get_tree().create_timer(0.15 / speed).timeout
			await play(b.act(u, plan["aid"], plan["target"]))
		else:
			b.do_wait(u)
		_sync_all()
		if await _check_end():
			return
	var ev := b.start_phase(0)
	if await _check_end():
		return
	_refresh()
	await _banner("Player Phase", UI.BLUE)
	await play(ev)
	if await _check_end():
		return
	state = "idle"
	_show_hint()
	_refresh()

func _check_end() -> bool:
	var r := b.check_result()
	if r == "":
		return false
	state = "over"
	_refresh()
	board.interactive = false
	Sfx.play("win" if r == "win" else "lose")
	await _banner("Victory!" if r == "win" else "Defeat", UI.GOLD if r == "win" else UI.RED)
	finished.emit(r, {"fallen": b.fallen, "turns": b.turn, "kills": b.kills})
	return true

# ---------------------------------------------------------------- animation
func _wait_t(t: float) -> void:
	await get_tree().create_timer(t / speed).timeout

func _banner(text: String, col: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	Sfx.play("phase")
	var tw := create_tween()
	banner.scale = Vector2(0.8, 0.8)
	banner.pivot_offset = banner.size * 0.5
	tw.tween_property(banner, "modulate:a", 1.0, 0.18 / speed)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.25 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55 / speed)
	tw.tween_property(banner, "modulate:a", 0.0, 0.25 / speed)
	await tw.finished

func _anim_path(uid: int, path: Array, step_t: float = 0.09) -> void:
	if path.size() < 2:
		board.sync_unit(b.get_unit(uid))
		return
	var v: Dictionary = board.vis[uid]
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1])
		var c := Vector2(path[i])
		var t := 0.0
		Sfx.play("move")
		while t < 1.0:
			t += get_process_delta_time() / (step_t / speed)
			v["p"] = a.lerp(c, clamp(t, 0.0, 1.0))
			await get_tree().process_frame
		v["p"] = c

func _sync_all() -> void:
	for u in b.units:
		board.sync_unit(u)

func play(ev: Array) -> void:
	for e in ev:
		match String(e["t"]):
			"move":
				if e.get("blink", false):
					var u = b.get_unit(e["u"])
					board.burst(board.unit_screen(u.id), Color("9a6aff"), 16)
					board.vis[u.id]["p"] = Vector2(e["path"][e["path"].size() - 1])
					board.burst(board.unit_screen(u.id), Color("9a6aff"), 16)
					await _wait_t(0.2)
				else:
					await _anim_path(e["u"], e["path"], 0.07 if e.get("push", false) else 0.09)
			"attack":
				var a = b.get_unit(e["a"])
				var d = b.get_unit(e["d"])
				var av: Dictionary = board.vis[a.id]
				var dir: Vector2 = (board.unit_screen(d.id) - board.unit_screen(a.id)).normalized()
				var tw := create_tween()
				tw.tween_method(func(k): av["bump"] = dir * 12.0 * sin(k * PI), 0.0, 1.0, 0.22 / speed)
				await _wait_t(0.11)
				var at: Vector2 = board.unit_screen(d.id)
				if e["hit"]:
					board.vis[d.id]["fl"] = 1.0
					Sfx.play("crit" if e["crit"] else ("magic" if e["magic"] else "hit"))
					board.burst(at + Vector2(0, -24), Color("ffcf6a") if not e["magic"] else Color("b07cff"), 22 if e["crit"] else 12)
					board.float_text(at, ("CRIT %d!" if e["crit"] else "%d") % e["dmg"], Color("ffd24a") if e["crit"] else Color.WHITE, e["crit"])
					if e["crit"]:
						board.shake = 9.0
					else:
						board.shake = 3.0
					var bs: Array = e.get("notes", [])
					if bs.has("Backstab"):
						board.float_text(at + Vector2(0, -20), "Backstab!", Color("ff8a5a"))
				else:
					Sfx.play("miss")
					board.float_text(at, "Miss", Color("a8c8ff"))
				await _wait_t(0.34)
			"die":
				var u = b.get_unit(e["u"])
				Sfx.play("death")
				board.burst(board.unit_screen(u.id) + Vector2(0, -20), Color("e0e0e0"), 26, 160.0)
				await _wait_t(0.4)
			"heal":
				var u = b.get_unit(e["u"])
				if int(e["amt"]) > 0:
					Sfx.play("heal")
					board.float_text(board.unit_screen(u.id), "+%d" % e["amt"], UI.GREEN)
					board.burst(board.unit_screen(u.id) + Vector2(0, -20), UI.GREEN, 10, 70.0)
					await _wait_t(0.25)
			"status":
				var u = b.get_unit(e["u"])
				board.float_text(board.unit_screen(u.id) + Vector2(0, -14), String(e["s"]).capitalize(), Color("c9a0ff"))
				await _wait_t(0.12)
			"build":
				Sfx.play("build")
				board.burst(board.tile_center(e["p"]), Color("c9a070"), 18)
				await _wait_t(0.25)
			"spawn":
				var u = b.get_unit(e["u"])
				board.sync_unit(u)
				board.burst(board.unit_screen(u.id) + Vector2(0, -16), Color("ffffff") if not e.get("wave", false) else Color("ff7a6a"), 16)
				if e.get("wave", false):
					board.float_text(board.unit_screen(u.id), "Reinforcements!", UI.RED)
				await _wait_t(0.2)
			"xp":
				var u = b.get_unit(e["u"])
				var lv: Dictionary = e["lv"]
				if not lv.is_empty():
					Sfx.play("level")
					var parts: Array = []
					for k in lv:
						parts.append("%s+%d" % [String(k).to_upper(), lv[k]])
					board.float_text(board.unit_screen(u.id) + Vector2(0, -24), "LEVEL UP! Lv %d" % u.lvl, UI.GOLD, true)
					info.text = "[color=#e0b552]%s reached level %d![/color]  %s" % [u.name, u.lvl, "  ".join(parts)]
					await _wait_t(0.8)
			"text":
				var col := Color("c9a0ff") if e.get("c", "") == "abil" else Color("ff8a7a")
				board.float_text(board.tile_center(e["p"]) + Vector2(0, -16), e["s"], col)
				await _wait_t(0.18)
			"blast":
				Sfx.play("magic")
				var col := Color("ff8a3a") if e["magic"] else Color("e8e0c0")
				for q in b.area("fireball", e["p"]):
					board.burst(board.tile_center(q) + Vector2(0, -8), col, 8, 90.0)
				board.shake = 5.0
				await _wait_t(0.2)
	_refresh()

# ---------------------------------------------------------------- pause
func _pause() -> void:
	if pause_layer != null:
		return
	pause_layer = Control.new()
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UI.full(dim)
	pause_layer.add_child(dim)
	var p := UI.panel()
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.lbl("Paused", 30, UI.GOLD))
	v.add_child(UI.lbl(b.objective_text(), 16, UI.DIM))
	v.add_child(UI.btn("Resume", _unpause))
	var sb := UI.btn("Sound: " + ("On" if Game.sound_on else "Off"), func(): pass)
	sb.pressed.connect(func():
		Game.sound_on = not Game.sound_on
		Game.save_settings()
		sb.text = "Sound: " + ("On" if Game.sound_on else "Off"))
	v.add_child(sb)
	var sp := UI.btn("Speed: %sx" % str(speed), func(): pass)
	sp.pressed.connect(func():
		speed = 2.0 if speed == 1.0 else 1.0
		sp.text = "Speed: %sx" % str(speed))
	v.add_child(sp)
	v.add_child(UI.btn("Restart mission", func():
		_unpause()
		finished.emit("restart", {})))
	v.add_child(UI.btn("Retreat to camp", func():
		_unpause()
		finished.emit("retreat", {})))
	pause_layer.add_child(UI.centered(p, 320))
	board.interactive = false

func _unpause() -> void:
	if pause_layer != null:
		pause_layer.queue_free()
		pause_layer = null
	board.interactive = state != "over"
