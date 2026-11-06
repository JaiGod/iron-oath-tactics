extends Node
## Campaign state: roster, gold, convoy, mission progress, settings and saving to user://.

const SAVE_PATH := "user://iron_oath_save.json"
const SETTINGS_PATH := "user://iron_oath_settings.cfg"
const MAX_DEPLOY := 6

var mode := "classic"          # classic (permadeath) | casual
var mission := 0               # index of next mission
var gold := 0
var roster: Array = []         # Array of Dictionaries
var convoy: Array = []         # item ids (weapons + gear)
var stats := {"kills": 0, "lost": 0, "battles": 0, "turns": 0}
var sound_on := true
var completed := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 7
	load_settings()

# ---------------------------------------------------------------- units
func make_unit(uname: String, cls: String, lvl: int = 1, lord: bool = false) -> Dictionary:
	var c: Dictionary = D.CLASSES[cls]
	var st := {}
	for k in D.STATS:
		st[k] = int(c["base"][k])
	var u := {"name": uname, "cls": cls, "lvl": 1, "xp": 0, "stats": st, "promoted": false,
		"weapon": D.START_WEAPON[c["weapon"]], "gear": "", "deploy": true, "lord": lord, "kills": 0}
	for i in range(lvl - 1):
		level_up(u, true)
	return u

## Applies one level of growth. avg=true uses expected values (enemies, mercs).
func level_up(u: Dictionary, avg: bool = false) -> Dictionary:
	var c: Dictionary = D.CLASSES[u["cls"]]
	var gains := {}
	u["lvl"] = int(u["lvl"]) + 1
	for k in D.STATS:
		var g: int = int(c["grow"][k])
		var n := 0
		if avg:
			var acc: float = float(u.get("_acc_" + k, 0.0)) + g / 100.0
			n = int(floor(acc))
			u["_acc_" + k] = acc - n
		else:
			if rng.randi_range(1, 100) <= g:
				n = 1
		if n > 0:
			u["stats"][k] = int(u["stats"][k]) + n
			gains[k] = n
	if not avg and gains.is_empty():
		u["stats"]["hp"] = int(u["stats"]["hp"]) + 1
		gains["hp"] = 1
	return gains

func class_name_of(u: Dictionary) -> String:
	var c: Dictionary = D.CLASSES[u["cls"]]
	return String(c["promo"]) if u.get("promoted", false) else String(c["name"])

func can_promote(u: Dictionary) -> bool:
	return not u.get("promoted", false) and int(u["lvl"]) >= 8 and convoy.has("oath_crest") and D.CLASSES[u["cls"]]["abil"].size() > 1

func promote(u: Dictionary) -> bool:
	if not can_promote(u):
		return false
	convoy.erase("oath_crest")
	u["promoted"] = true
	var b: Dictionary = D.CLASSES[u["cls"]]["pbonus"]
	for k in b:
		u["stats"][k] = int(u["stats"][k]) + int(b[k])
	save_game()
	return true

func weapon_ok(u: Dictionary, wid: String) -> bool:
	return D.WEAPONS.has(wid) and D.WEAPONS[wid]["type"] == D.CLASSES[u["cls"]]["weapon"]

func equip(u: Dictionary, item: String) -> bool:
	if not convoy.has(item):
		return false
	if D.WEAPONS.has(item):
		if not weapon_ok(u, item):
			return false
		convoy.erase(item)
		convoy.append(u["weapon"])
		u["weapon"] = item
	elif D.GEAR.has(item) and not D.GEAR[item].get("crest", false):
		convoy.erase(item)
		if u["gear"] != "":
			convoy.append(u["gear"])
		u["gear"] = item
	else:
		return false
	return true

func unequip_gear(u: Dictionary) -> void:
	if u["gear"] != "":
		convoy.append(u["gear"])
		u["gear"] = ""

# ---------------------------------------------------------------- shop
func shop_items() -> Array:
	var tier: int = int(D.MISSIONS[min(mission, D.MISSIONS.size() - 1)]["shop"]) if mission < D.MISSIONS.size() else 3
	var out := []
	for k in D.WEAPONS:
		var w: Dictionary = D.WEAPONS[k]
		if int(w.get("tier", 0)) <= tier and int(w["cost"]) > 0:
			out.append(k)
	for k in D.GEAR:
		if int(D.GEAR[k].get("tier", 0)) <= tier:
			out.append(k)
	return out

func item_name(id: String) -> String:
	if D.WEAPONS.has(id):
		return D.WEAPONS[id]["name"]
	if D.GEAR.has(id):
		return D.GEAR[id]["name"]
	return id

func item_cost(id: String) -> int:
	if D.WEAPONS.has(id):
		return int(D.WEAPONS[id]["cost"])
	return int(D.GEAR[id]["cost"]) if D.GEAR.has(id) else 0

func buy(id: String) -> bool:
	var c := item_cost(id)
	if c <= 0 or gold < c:
		return false
	gold -= c
	convoy.append(id)
	return true

func sell(id: String) -> bool:
	if not convoy.has(id):
		return false
	convoy.erase(id)
	gold += item_cost(id) / 2
	return true

func merc_cost() -> int:
	return 500 + mission * 150

func hire(cls: String) -> bool:
	var cost := merc_cost()
	if gold < cost or not D.ENEMY_NAMES.has(cls):
		return false
	gold -= cost
	var nm: String = D.MERC_NAMES[rng.randi_range(0, D.MERC_NAMES.size() - 1)]
	var lv: int = max(1, mission)
	var u := make_unit(nm, cls, lv)
	u["deploy"] = deployed().size() < MAX_DEPLOY
	roster.append(u)
	return true

func deployed() -> Array:
	var out := []
	for u in roster:
		if u.get("deploy", true) and out.size() < MAX_DEPLOY:
			out.append(u)
	# the lord always deploys
	var lord = get_lord()
	if lord != null and not out.has(lord):
		if out.size() >= MAX_DEPLOY:
			out.pop_back()
		out.insert(0, lord)
	return out

func get_lord():
	for u in roster:
		if u.get("lord", false):
			return u
	return null

func toggle_deploy(u: Dictionary) -> void:
	if u.get("lord", false):
		return
	if u["deploy"]:
		u["deploy"] = false
	elif deployed().size() < MAX_DEPLOY:
		u["deploy"] = true

# ---------------------------------------------------------------- campaign
func new_game(m: String) -> void:
	mode = m
	mission = 0
	gold = 500
	completed = false
	roster = []
	convoy = ["javelin", "vigor_ring"]
	stats = {"kills": 0, "lost": 0, "battles": 0, "turns": 0}
	rng.seed = 1234
	for h in D.HEROES:
		roster.append(make_unit(h["name"], h["cls"], 1, h.get("lord", false)))
	save_game()

## Called after a won battle. results: {"fallen": [names], "turns": n, "kills": n}
func finish_mission(results: Dictionary) -> Array:
	var notes := []
	var m: Dictionary = D.MISSIONS[mission]
	gold += int(m["gold"]) + int(results.get("bonus", 0))
	stats["battles"] = int(stats["battles"]) + 1
	stats["turns"] = int(stats["turns"]) + int(results.get("turns", 0))
	stats["kills"] = int(stats["kills"]) + int(results.get("kills", 0))
	if mode == "classic":
		for nm in results.get("fallen", []):
			for u in roster.duplicate():
				if u["name"] == nm and not u.get("lord", false):
					roster.erase(u)
					stats["lost"] = int(stats["lost"]) + 1
					notes.append(nm + " has fallen and will be remembered.")
	if D.RECRUITS.has(mission):
		var r: Dictionary = D.RECRUITS[mission]
		var nu := make_unit(r["name"], r["cls"], max(1, mission + 1))
		nu["deploy"] = deployed().size() < MAX_DEPLOY
		roster.append(nu)
		notes.append(r["name"] + " the " + D.CLASSES[r["cls"]]["name"] + " joins the company!")
	if mission == 4:
		convoy.append("oath_crest")
		notes.append("Found an Oath Crest (promotion item).")
	mission += 1
	if mission >= D.MISSIONS.size():
		completed = true
	save_game()
	return notes

# ---------------------------------------------------------------- save / load
func to_dict() -> Dictionary:
	return {"v": 1, "mode": mode, "mission": mission, "gold": gold, "roster": roster, "convoy": convoy,
		"stats": stats, "completed": completed}

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	mode = String(data.get("mode", "classic"))
	mission = int(data.get("mission", 0))
	gold = int(data.get("gold", 0))
	completed = bool(data.get("completed", false))
	roster = []
	for u in data.get("roster", []):
		var d: Dictionary = u
		d["lvl"] = int(d["lvl"]); d["xp"] = int(d["xp"]); d["kills"] = int(d.get("kills", 0))
		for k in D.STATS:
			d["stats"][k] = int(d["stats"][k])
		roster.append(d)
	convoy = []
	for it in data.get("convoy", []):
		convoy.append(String(it))
	var s = data.get("stats", {})
	for k in stats:
		stats[k] = int(s.get(k, 0))
	return roster.size() > 0

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		sound_on = bool(cf.get_value("audio", "sound", true))

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sound", sound_on)
	cf.save(SETTINGS_PATH)
