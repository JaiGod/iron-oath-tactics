extends Control
## Camp between missions: roster & deployment, armory (equipment, promotion), shop and tavern.

signal begin
signal to_title

var tab := "roster"
var pick := 0
var content: VBoxContainer
var gold_lbl: Label
var tabs_box: HBoxContainer
var msg: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.07, 0.72)
	UI.full(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	UI.full(margin)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 10)
	add_child(margin)
	var root := UI.vbox(8)
	margin.add_child(root)
	var head := UI.hbox(8)
	root.add_child(head)
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: Dictionary = D.MISSIONS[Game.mission]
	tv.add_child(UI.lbl("Iron Oath Camp", 26, UI.GOLD, 6))
	tv.add_child(UI.lbl("Next: Mission %d/10 — %s (%s) · %s mode" % [Game.mission + 1, m["name"], String(m["type"]).capitalize(), Game.mode.capitalize()], 15, UI.DIM))
	head.add_child(tv)
	gold_lbl = UI.lbl("", 20, UI.GOLD)
	gold_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(gold_lbl)
	tabs_box = UI.hbox(6)
	root.add_child(tabs_box)
	for t in [["roster", "Roster & Armory"], ["shop", "Shop"], ["tavern", "Tavern"]]:
		var id: String = t[0]
		var b := UI.btn(t[1], func():
			tab = id
			_rebuild())
		b.name = id
		tabs_box.add_child(b)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	content = UI.vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	msg = UI.lbl("", 15, UI.GREEN)
	root.add_child(msg)
	var foot := UI.hbox(8)
	root.add_child(foot)
	foot.add_child(UI.btn("Title", func(): to_title.emit(), 80))
	foot.add_child(UI.btn("Save", func():
		Game.save_game()
		_say("Progress saved."), 80))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var go := UI.btn("Begin Mission %d  ▶" % (Game.mission + 1), func(): begin.emit(), 220)
	go.add_theme_font_size_override("font_size", 20)
	foot.add_child(go)
	_rebuild()

func _say(s: String, ok: bool = true) -> void:
	msg.text = s
	msg.add_theme_color_override("font_color", UI.GREEN if ok else UI.RED)

func _portrait() -> bool:
	var vs := get_viewport_rect().size
	return vs.y > vs.x

func _rebuild() -> void:
	gold_lbl.text = "%d g" % Game.gold
	for c in tabs_box.get_children():
		(c as Button).disabled = c.name == tab
	for c in content.get_children():
		c.queue_free()
	match tab:
		"roster": _roster()
		"shop": _shop()
		"tavern": _tavern()

func _stat_line(u: Dictionary) -> String:
	var st: Dictionary = u["stats"].duplicate()
	var mv: int = int(D.CLASSES[u["cls"]]["mov"]) + (int(D.CLASSES[u["cls"]]["pmov"]) if u["promoted"] else 0)
	if u["gear"] != "":
		var bon: Dictionary = D.GEAR[u["gear"]]["bonus"]
		for k in bon:
			if k == "mov":
				mv += int(bon[k])
			else:
				st[k] = int(st[k]) + int(bon[k])
	return "HP %d  STR %d  MAG %d  SKL %d  SPD %d  DEF %d  RES %d  MOV %d" % [st["hp"], st["str"], st["mag"], st["skl"], st["spd"], st["def"], st["res"], mv]

func _roster() -> void:
	if Game.roster.is_empty():
		return
	pick = clamp(pick, 0, Game.roster.size() - 1)
	var box := BoxContainer.new()
	box.vertical = _portrait()
	box.add_theme_constant_override("separation", 10)
	content.add_child(box)
	var left := UI.vbox(4)
	left.custom_minimum_size.x = 0 if _portrait() else 300
	box.add_child(left)
	left.add_child(UI.lbl("Deployed %d/%d (tap a unit, then toggle)" % [Game.deployed().size(), Game.MAX_DEPLOY], 14, UI.DIM))
	var grid := GridContainer.new()
	grid.columns = 2 if _portrait() else 1
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	for i in Game.roster.size():
		var u: Dictionary = Game.roster[i]
		var dep: bool = Game.deployed().has(u)
		var t := "%s%s  Lv%d %s" % ["★ " if dep else "· ", u["name"], u["lvl"], Game.class_name_of(u)]
		var idx := i
		var b := UI.btn(t, func():
			pick = idx
			_rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == pick:
			b.add_theme_color_override("font_color", UI.GOLD)
		grid.add_child(b)
	var u: Dictionary = Game.roster[pick]
	var p := UI.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(p)
	var v := UI.vbox(6)
	p.add_child(v)
	var c: Dictionary = D.CLASSES[u["cls"]]
	v.add_child(UI.rich("[b][color=#e0b552]%s[/color][/b]  Lv %d %s%s   XP %d/100\n[color=#b3a58c]%s[/color]" % [u["name"], u["lvl"], Game.class_name_of(u), "  (Leader)" if u["lord"] else "", u["xp"], c["desc"]], 17))
	v.add_child(UI.rich(_stat_line(u), 16))
	var w: Dictionary = D.WEAPONS[u["weapon"]]
	var gtxt: String = "none" if u["gear"] == "" else "%s (%s)" % [D.GEAR[u["gear"]]["name"], D.GEAR[u["gear"]]["desc"]]
	v.add_child(UI.rich("Weapon: [color=#e0b552]%s[/color] (%s, Mt %d, Hit %d, Rng %d-%d)\nGear: [color=#e0b552]%s[/color]" % [w["name"], w["type"], w["mt"], w["hit"], w["r"][0], w["r"][1], gtxt], 16))
	var ab := ""
	for i in c["abil"].size():
		var aid: String = c["abil"][i]
		var locked: bool = i == 1 and not u["promoted"]
		ab += "[color=#%s]%s[/color]%s: %s\n" % ["7a7068" if locked else "c9a0ff", D.ABIL[aid]["name"], " (unlocks on promotion)" if locked else "", D.ABIL[aid]["desc"]]
	v.add_child(UI.rich(ab.strip_edges(), 15))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	if not u["lord"]:
		row.add_child(UI.btn("Bench" if Game.deployed().has(u) else "Deploy", func():
			Game.toggle_deploy(u)
			_rebuild()))
	var pr := UI.btn("Promote to %s" % c["promo"], func():
		if Game.promote(u):
			Sfx.play("level")
			_say("%s is now a %s!" % [u["name"], c["promo"]])
		_rebuild())
	pr.disabled = not Game.can_promote(u)
	pr.tooltip_text = "Needs level 8 and an Oath Crest"
	row.add_child(pr)
	if u["gear"] != "":
		row.add_child(UI.btn("Remove gear", func():
			Game.unequip_gear(u)
			_rebuild()))
	v.add_child(UI.lbl("Equip from convoy:", 15, UI.DIM))
	var eq := HFlowContainer.new()
	eq.add_theme_constant_override("h_separation", 6)
	eq.add_theme_constant_override("v_separation", 6)
	v.add_child(eq)
	var seen := {}
	for it in Game.convoy:
		if seen.has(it):
			continue
		seen[it] = true
		var okw: bool = D.WEAPONS.has(it) and Game.weapon_ok(u, it)
		var okg: bool = D.GEAR.has(it) and not D.GEAR[it].get("crest", false)
		if okw or okg:
			var item: String = it
			eq.add_child(UI.btn(Game.item_name(item), func():
				Game.equip(u, item)
				Sfx.play("build")
				_say("%s equipped %s." % [u["name"], Game.item_name(item)])
				_rebuild()))
	if eq.get_child_count() == 0:
		eq.add_child(UI.lbl("Nothing suitable. Buy gear in the Shop.", 14, UI.DIM))

func _item_desc(id: String) -> String:
	if D.WEAPONS.has(id):
		var w: Dictionary = D.WEAPONS[id]
		return "%s · Mt %d Hit %d Crit %d Rng %d-%d" % [w["type"], w["mt"], w["hit"], w["crit"], w["r"][0], w["r"][1]]
	return D.GEAR[id]["desc"]

func _shop() -> void:
	content.add_child(UI.lbl("Armory stock improves as the campaign advances.", 14, UI.DIM))
	var grid := GridContainer.new()
	grid.columns = 1 if _portrait() else 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	for id in Game.shop_items():
		var row := UI.hbox(6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := UI.rich("[color=#e0b552]%s[/color]  [color=#b3a58c]%s[/color]" % [Game.item_name(id), _item_desc(id)], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var item: String = id
		var b := UI.btn("Buy %dg" % Game.item_cost(id), func():
			if Game.buy(item):
				_say("Bought %s." % Game.item_name(item))
			else:
				_say("Not enough gold.", false)
			_rebuild(), 110)
		b.disabled = Game.gold < Game.item_cost(id)
		row.add_child(b)
		grid.add_child(row)
	content.add_child(UI.lbl("Convoy (sell for half price):", 16, UI.GOLD))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	content.add_child(flow)
	for it in Game.convoy:
		var item: String = it
		flow.add_child(UI.btn("%s  +%dg" % [Game.item_name(item), Game.item_cost(item) / 2], func():
			Game.sell(item)
			_rebuild()))
	if Game.convoy.is_empty():
		flow.add_child(UI.lbl("Empty.", 14, UI.DIM))

func _tavern() -> void:
	content.add_child(UI.lbl("Hire a mercenary at level %d for %d gold. Handy when Classic mode claims a friend." % [max(1, Game.mission), Game.merc_cost()], 15, UI.DIM))
	var grid := GridContainer.new()
	grid.columns = 1 if _portrait() else 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	for cls in ["knight", "archer", "mage", "healer", "rogue", "lancer", "engineer", "beastmaster"]:
		var row := UI.hbox(6)
		var c: Dictionary = D.CLASSES[cls]
		var l := UI.rich("[color=#e0b552]%s[/color] (%s)  [color=#b3a58c]%s[/color]" % [c["name"], c["weapon"], c["desc"]], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var k: String = cls
		var b := UI.btn("Hire", func():
			if Game.hire(k):
				_say("A new %s joins the company!" % c["name"])
			else:
				_say("Not enough gold.", false)
			_rebuild(), 80)
		b.disabled = Game.gold < Game.merc_cost()
		row.add_child(b)
		grid.add_child(row)
