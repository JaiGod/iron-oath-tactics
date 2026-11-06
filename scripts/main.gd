extends Node
## Screen manager: title, campaign setup, story scenes, camp, battles, results and ending.

const BoardScript := preload("res://scripts/board.gd")
const HudScript := preload("res://scripts/hud.gd")
const CampScript := preload("res://scripts/camp.gd")

var world: Node2D
var ui_layer: CanvasLayer
var ui: Control
var board = null
var hud = null
var battle: Battle = null
var snapshot := []
var screen := ""
var _story_cb: Callable
var _story_lines: Array = []
var _story_i := 0
var _story_box: RichTextLabel
var _story_name: Label

func _ready() -> void:
	var sky := CanvasLayer.new()
	sky.layer = -1
	add_child(sky)
	var tr := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color("2a2238"))
	g.set_color(1, Color("0d0b12"))
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.add_child(tr)
	world = Node2D.new()
	add_child(world)
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	ui = Control.new()
	ui.theme = UI.make_theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui)
	get_tree().root.size_changed.connect(_on_resize)
	_on_resize()
	show_title()

func _on_resize() -> void:
	var w := get_window()
	var s := w.size
	w.content_scale_size = Vector2i(560, 980) if s.y > s.x else Vector2i(1280, 720)
	if board != null and hud == null:
		board.fit(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))

func _clear() -> void:
	for c in ui.get_children():
		c.queue_free()
	if board != null:
		board.queue_free()
		board = null
	hud = null

func _backdrop(mi: int) -> void:
	var b := Battle.new()
	var r: Array = []
	for h in D.HEROES:
		r.append(Game.make_unit(h["name"], h["cls"], 1, h.get("lord", false)))
	for k in ["mage", "rogue"]:
		r.append(Game.make_unit(k.capitalize(), k, 1))
	b.setup(mi, r)
	board = BoardScript.new()
	world.add_child(board)
	board.setup(b)
	board.interactive = false
	board.fit(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))

func _dim(a: float = 0.45) -> void:
	var d := ColorRect.new()
	d.color = Color(0.04, 0.03, 0.06, a)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full(d)
	ui.add_child(d)

# ---------------------------------------------------------------- title
func show_title() -> void:
	_clear()
	screen = "title"
	_backdrop(9)
	_dim(0.5)
	var v := UI.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t1 := UI.lbl("IRON OATH", 72, UI.GOLD, 14)
	t1.autowrap_mode = TextServer.AUTOWRAP_OFF
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t2 := UI.lbl("— T A C T I C S —", 22, Color("e8d9b8"), 6)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t3 := UI.lbl("A turn-based fantasy tactics campaign", 16, UI.DIM, 4)
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	v.add_child(t2)
	v.add_child(t3)
	var sp := Control.new()
	sp.custom_minimum_size.y = 16
	v.add_child(sp)
	if Game.has_save():
		v.add_child(UI.btn("Continue Campaign", func():
			if Game.load_game():
				if Game.completed:
					show_ending()
				else:
					show_camp()))
	v.add_child(UI.btn("New Campaign", show_new))
	v.add_child(UI.btn("How to Play", show_howto))
	var sb := UI.btn("Sound: " + ("On" if Game.sound_on else "Off"), func(): pass)
	sb.pressed.connect(func():
		Game.sound_on = not Game.sound_on
		Game.save_settings()
		sb.text = "Sound: " + ("On" if Game.sound_on else "Off"))
	v.add_child(sb)
	var cr := UI.lbl("Made by Jaineil Rana (JaKing) · JaiGod", 14, UI.DIM, 4)
	cr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cr)
	ui.add_child(UI.centered(v, 360))

func show_new() -> void:
	_clear()
	_backdrop(3)
	_dim(0.6)
	var p := UI.panel()
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.lbl("Choose your oath", 30, UI.GOLD))
	v.add_child(UI.rich("[color=#e0584a][b]Classic[/b][/color] — Permadeath. Fallen companions are lost forever. Every choice matters.", 17))
	v.add_child(UI.btn("Classic (permadeath)", func(): _begin_campaign("classic")))
	v.add_child(UI.rich("[color=#6fd07a][b]Casual[/b][/color] — Fallen companions retreat and return after the battle. Aldric must still survive.", 17))
	v.add_child(UI.btn("Casual", func(): _begin_campaign("casual")))
	if Game.has_save():
		v.add_child(UI.lbl("Starting a new campaign overwrites your current save.", 14, UI.RED))
	v.add_child(UI.btn("Back", show_title))
	ui.add_child(UI.centered(p, 520))

func _begin_campaign(mode: String) -> void:
	Game.new_game(mode)
	show_story(D.MISSIONS[0]["intro"], start_mission)

func show_howto() -> void:
	_clear()
	_backdrop(1)
	_dim(0.7)
	var p := UI.panel()
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var outer := UI.vbox(8)
	outer.add_child(UI.lbl("How to Play", 30, UI.GOLD))
	outer.add_child(sc)
	outer.add_child(UI.btn("Back", show_title))
	p.add_child(outer)
	v.add_child(UI.rich("""[color=#e0b552][b]Controls[/b][/color]
Tap or click a [color=#7fb2ff]blue unit[/color] to select it. Blue tiles show where it can move, red tiles what it can hit. Tap a tile to move, then pick [b]Attack[/b], an [b]ability[/b] or [b]Wait[/b]. Tap a target to see the forecast; tap again or press [b]Confirm[/b]. Tap an enemy to see its threat range. Drag to pan, +/- or the mouse wheel to zoom. [b]Esc[/b] cancels / pauses, [b]E[/b] ends the turn.

[color=#e0b552][b]Weapon triangle[/b][/color]
Swords & daggers beat axes & hammers, axes beat lances, lances beat swords: +15% damage and +15 hit with the advantage.

[color=#e0b552][b]Facing & flanking[/b][/color]
Every unit faces a direction (the arrow at its feet). Hitting from the [b]side[/b] gives +20% damage, from [b]behind[/b] +50% and +20 crit. Rogues double damage from behind.

[color=#e0b552][b]Height & terrain[/b][/color]
Each level of height above the target adds +10% damage and +5 hit. Archers on high ground gain +1 range. Forests, forts and the throne raise defense; rocks, forests and barricades give [b]cover[/b] against ranged attacks (-20 hit). Marsh is slow and exposed. Forts and thrones heal at the start of your turn.

[color=#e0b552][b]Combat[/b][/color]
Defenders counter if you are in their range. A unit 5+ speed faster strikes twice. Magic hits RES instead of DEF. Crits deal triple damage.

[color=#e0b552][b]Campaign[/b][/color]
10 missions: [b]Rout[/b] (defeat all or the boss), [b]Defend[/b] (keep foes off the gate), [b]Escort[/b] (bring the envoy to the exit) and [b]Seize[/b] (Aldric claims the throne). If Aldric falls the battle is lost. Units level up from combat; at level 8 an [b]Oath Crest[/b] promotes them, raising stats and unlocking a second ability. Buy weapons and gear in camp. Progress saves automatically after every victory.""", 16))
	ui.add_child(UI.centered(p, 700))

# ---------------------------------------------------------------- story
func show_story(lines: Array, done: Callable) -> void:
	_clear()
	screen = "story"
	_backdrop(min(Game.mission, 9))
	_dim(0.35)
	_story_lines = lines
	_story_i = 0
	_story_cb = done
	var root := Control.new()
	UI.full(root)
	ui.add_child(root)
	var p := UI.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_left = 16; p.offset_right = -16; p.offset_bottom = -16
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(p)
	var v := UI.vbox(6)
	p.add_child(v)
	var hdr := UI.lbl("Mission %d — %s" % [min(Game.mission, 9) + 1, D.MISSIONS[min(Game.mission, 9)]["name"]], 14, UI.DIM)
	v.add_child(hdr)
	_story_name = UI.lbl("", 22, UI.GOLD)
	v.add_child(_story_name)
	_story_box = UI.rich("", 19)
	_story_box.custom_minimum_size.y = 60
	v.add_child(_story_box)
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UI.btn("Skip", func(): _story_done(), 80))
	row.add_child(UI.btn("Next ▶", _story_next, 110))
	v.add_child(row)
	_story_show()

func _story_show() -> void:
	var l: Array = _story_lines[_story_i]
	_story_name.text = l[0]
	_story_box.text = l[1]
	_story_box.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_property(_story_box, "visible_ratio", 1.0, 0.5)

func _story_next() -> void:
	if _story_box.visible_ratio < 1.0:
		_story_box.visible_ratio = 1.0
		return
	_story_i += 1
	if _story_i >= _story_lines.size():
		_story_done()
	else:
		_story_show()

func _story_done() -> void:
	if screen != "story":
		return
	screen = ""
	_story_cb.call()

func _unhandled_input(event: InputEvent) -> void:
	if screen == "story" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_story_next()
	elif screen == "story" and event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER):
		_story_next()

# ---------------------------------------------------------------- camp & battle
func show_camp() -> void:
	_clear()
	screen = "camp"
	_backdrop(min(Game.mission, 9))
	var c = CampScript.new()
	ui.add_child(c)
	c.begin.connect(func(): show_story(D.MISSIONS[Game.mission]["intro"], start_mission))
	c.to_title.connect(show_title)

func start_mission() -> void:
	_clear()
	screen = "battle"
	snapshot = Game.roster.duplicate(true)
	battle = Battle.new()
	battle.setup(Game.mission, Game.deployed())
	board = BoardScript.new()
	world.add_child(board)
	hud = HudScript.new()
	ui.add_child(hud)
	hud.finished.connect(_on_battle_end)
	hud.start(battle, board)

func _restore() -> void:
	Game.roster = snapshot.duplicate(true)

func _on_battle_end(r: String, data: Dictionary) -> void:
	match r:
		"restart":
			_restore()
			start_mission()
		"retreat":
			_restore()
			show_camp()
		"lose":
			_restore()
			_result_panel(false, data, [])
		"win":
			var m: Dictionary = D.MISSIONS[Game.mission]
			var notes := Game.finish_mission(data)
			_result_panel(true, data, notes, m)

func _result_panel(win: bool, data: Dictionary, notes: Array, m: Dictionary = {}) -> void:
	var lay := Control.new()
	UI.full(lay)
	ui.add_child(lay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	UI.full(dim)
	lay.add_child(dim)
	var p := UI.panel()
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.lbl("Victory!" if win else "Defeat", 40, UI.GOLD if win else UI.RED, 8))
	if win:
		var s := "[color=#e0b552]%s[/color] cleared in %d turns.\nEnemies defeated: %d\nReward: [color=#e0b552]%d gold[/color]  (total %d g)" % [m["name"], data["turns"], data["kills"], m["gold"], Game.gold]
		if not data["fallen"].is_empty():
			s += "\n[color=#e0584a]Fell in battle: %s[/color]%s" % [", ".join(data["fallen"]), " — lost forever (Classic)." if Game.mode == "classic" else " — they will recover (Casual)."]
		for n in notes:
			s += "\n[color=#6fd07a]" + n + "[/color]"
		v.add_child(UI.rich(s, 17))
		v.add_child(UI.btn("Continue", func(): show_story(m["outro"], func():
			if Game.completed:
				show_ending()
			else:
				show_camp())))
	else:
		v.add_child(UI.rich("The company is driven back. Aldric regroups and prepares to try again.\n[color=#b3a58c]Tip: keep healers behind the knight, attack from the side or behind, and use high ground.[/color]", 17))
		v.add_child(UI.btn("Retry mission", start_mission))
		v.add_child(UI.btn("Return to camp", show_camp))
		v.add_child(UI.btn("Title", show_title))
	lay.add_child(UI.centered(p, 460))

func show_ending() -> void:
	_clear()
	screen = "ending"
	_backdrop(9)
	_dim(0.55)
	var p := UI.panel()
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.lbl("The Oath Is Kept", 36, UI.GOLD, 8))
	var alive: Array = []
	for u in Game.roster:
		alive.append("%s (Lv %d %s)" % [u["name"], u["lvl"], Game.class_name_of(u)])
	v.add_child(UI.rich("Warlord Vael is defeated and Elderreach is free.\n\nMode: %s\nBattles won: %d · Turns: %d · Foes defeated: %d · Companions lost: %d\n\n[color=#e0b552]The company:[/color] %s" % [Game.mode.capitalize(), Game.stats["battles"], Game.stats["turns"], Game.stats["kills"], Game.stats["lost"], ", ".join(alive)], 17))
	v.add_child(UI.btn("Back to title", show_title))
	ui.add_child(UI.centered(p, 560))
