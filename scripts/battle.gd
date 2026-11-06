class_name Battle
extends RefCounted
## Pure battle rules: map generation, movement, combat math, abilities, objectives and enemy AI.
## Rendering-free so it can be smoke-tested headless.

const W := 13
const H := 11
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const TIERS := {"sword": ["iron_sword", "steel_sword", "silver_sword"], "lance": ["iron_lance", "steel_lance", "silver_lance"],
	"axe": ["iron_axe", "steel_axe", "silver_axe"], "hammer": ["forge_hammer", "steam_hammer", "steam_hammer"],
	"dagger": ["iron_dagger", "steel_dagger", "silver_dagger"], "bow": ["short_bow", "longbow", "silver_bow"],
	"tome": ["fire_tome", "thunder_tome", "inferno_tome"], "staff": ["oak_staff", "crystal_staff", "crystal_staff"]}

class Unit:
	var id := 0
	var name := ""
	var cls := ""
	var team := 0
	var lvl := 1
	var xp := 0
	var hp := 1
	var st := {}
	var mov := 4
	var jump := 1
	var weapon := "none"
	var pos := Vector2i.ZERO
	var start := Vector2i.ZERO
	var facing := 2
	var moved := false
	var acted := false
	var cds := {}
	var status := {}
	var boss := false
	var lord := false
	var npc := false
	var summon := false
	var ai := "aggr"
	var promoted := false
	var abil: Array = []
	var ref = null
	var kills := 0
	var alive := true
	func mhp() -> int:
		return int(st["hp"])

var mi := 0
var m: Dictionary = {}
var terr: Array = []
var hgt: Array = []
var units: Array = []
var turn := 1
var phase := 0
var rng := RandomNumberGenerator.new()
var goal := Vector2i(-1, -1)
var exits: Array = []
var result := ""
var fallen: Array = []
var kills := 0
var next_id := 1
var pspawn: Array = []
var espawn: Array = []
var danger := {}
var waves_done := {}

# ================================================================ setup
func setup(mission_index: int, roster_units: Array, seed_extra: int = 0) -> void:
	mi = mission_index
	m = D.MISSIONS[mi]
	rng.seed = int(m["seed"]) * 7919 + seed_extra
	gen_map()
	var spots := pspawn.duplicate()
	if m["type"] == "escort":
		var e := Unit.new()
		var nm := "Envoy Pell" if mi < 5 else "Elder Maren"
		_init_unit(e, Game.make_unit(nm, "envoy", 1), 0)
		e.npc = true
		e.st["hp"] = 20 + mi * 3
		e.st["def"] = 4 + mi
		e.st["res"] = 4 + mi
		e.hp = e.mhp()
		e.pos = spots.pop_back() if spots.size() > roster_units.size() else spots.pop_front()
		add_unit(e)
	for r in roster_units:
		if spots.is_empty():
			break
		var u := Unit.new()
		_init_unit(u, r, 0)
		u.ref = r
		u.lord = r.get("lord", false)
		u.pos = spots.pop_front()
		add_unit(u)
	var es := espawn.duplicate()
	for e in m["enemies"]:
		for i in int(e[2]):
			var p: Vector2i = es.pop_front() if not es.is_empty() else Vector2i(-1, -1)
			if String(e[3]).find("boss") >= 0:
				if m["type"] == "seize":
					p = goal
				else:
					es.sort_custom(func(a, b): return a.x > b.x)
					if not es.is_empty():
						p = es.pop_front()
			if p.x < 0:
				continue
			spawn_enemy(String(e[0]), int(e[1]), String(e[3]), p)
	for u in units:
		u.facing = 0 if u.team == 0 else 2

func spawn_enemy(cls: String, lvl: int, flags: String, p: Vector2i) -> Unit:
	var u := Unit.new()
	var r := Game.make_unit(D.ENEMY_NAMES.get(cls, "Foe"), cls, lvl)
	var tier := 0 if lvl < 4 else (1 if lvl < 8 else 2)
	var wt: String = D.CLASSES[cls]["weapon"]
	if TIERS.has(wt):
		r["weapon"] = TIERS[wt][tier]
	r["promoted"] = lvl >= 9
	# enemies grow a little slower than the player's company
	for k in D.STATS:
		r["stats"][k] = int(round(int(r["stats"][k]) * (0.9 if k == "hp" else 0.85)))
	if flags.find("boss") >= 0:
		for k in D.STATS:
			r["stats"][k] = int(r["stats"][k]) + (4 if k == "hp" else 2)
		if TIERS.has(wt):
			r["weapon"] = TIERS[wt][2]
		r["name"] = D.BOSS_NAMES[mi] if D.BOSS_NAMES[mi] != "" else "Commander"
	if flags.find("vael") >= 0:
		r["weapon"] = "oathblade"
		for k in D.STATS:
			r["stats"][k] = int(r["stats"][k]) + (8 if k == "hp" else 2)
	_init_unit(u, r, 1)
	u.boss = flags.find("boss") >= 0
	u.ai = "guard" if flags.find("guard") >= 0 else "aggr"
	if m["type"] == "defend" and not u.boss:
		u.ai = "goal" if rng.randf() < 0.5 else "aggr"
	u.pos = p
	u.start = p
	u.facing = 2
	add_unit(u)
	return u

func _init_unit(u: Unit, r: Dictionary, team: int) -> void:
	var c: Dictionary = D.CLASSES[r["cls"]]
	u.name = r["name"]
	u.cls = r["cls"]
	u.team = team
	u.lvl = int(r["lvl"])
	u.xp = int(r.get("xp", 0))
	u.promoted = r.get("promoted", false)
	u.st = {}
	for k in D.STATS:
		u.st[k] = int(r["stats"][k])
	u.mov = int(c["mov"]) + (int(c["pmov"]) if u.promoted else 0)
	u.jump = int(c["jump"])
	var g: String = r.get("gear", "")
	if g != "" and D.GEAR.has(g):
		var b: Dictionary = D.GEAR[g]["bonus"]
		for k in b:
			if k == "mov":
				u.mov += int(b[k])
			else:
				u.st[k] = int(u.st[k]) + int(b[k])
	u.weapon = r["weapon"]
	u.hp = u.mhp()
	u.abil = []
	var ab: Array = c["abil"]
	if ab.size() > 0:
		u.abil.append(ab[0])
	if ab.size() > 1 and u.promoted:
		u.abil.append(ab[1])

func add_unit(u: Unit) -> void:
	u.id = next_id
	next_id += 1
	if u.start == Vector2i.ZERO:
		u.start = u.pos
	units.append(u)

# ================================================================ map generation
func gen_map() -> void:
	terr = []
	hgt = []
	terr.resize(W * H)
	hgt.resize(W * H)
	var cw := 5
	var coarse := []
	for i in cw * cw:
		coarse.append(rng.randf())
	var hill: float = m.get("hill", 1.0)
	for y in H:
		for x in W:
			var fx := float(x) / (W - 1) * (cw - 1)
			var fy := float(y) / (H - 1) * (cw - 1)
			var ix: int = min(int(fx), cw - 2)
			var iy: int = min(int(fy), cw - 2)
			var tx := fx - ix
			var ty := fy - iy
			var a: float = lerp(coarse[iy * cw + ix], coarse[iy * cw + ix + 1], tx)
			var b: float = lerp(coarse[(iy + 1) * cw + ix], coarse[(iy + 1) * cw + ix + 1], tx)
			var v: float = lerp(a, b, ty)
			hgt[y * W + x] = int(clamp(round(v * hill * 2.6 - 0.4), 0, 3))
			terr[y * W + x] = "g"
	# terrain features
	for i in W * H:
		var r := rng.randf()
		if r < float(m.get("forest", 0.1)):
			terr[i] = "f"
		elif r < float(m.get("forest", 0.1)) + float(m.get("rocks", 0.05)):
			terr[i] = "x"
		elif r < float(m.get("forest", 0.1)) + float(m.get("rocks", 0.05)) + float(m.get("marsh", 0.0)):
			terr[i] = "s"
			hgt[i] = 0
	# grow forest clusters a little
	for i in W * H:
		if terr[i] == "f" and rng.randf() < 0.5:
			var p: Vector2i = Vector2i(i % W, i / W) + DIRS[rng.randi_range(0, 3)]
			if inb(p) and t(p) == "g":
				terr[idx(p)] = "f"
	# river
	if m.get("river", false):
		var rx := W / 2 + rng.randi_range(-1, 1)
		for y in H:
			for dx in [0, 1]:
				var p := Vector2i(clamp(rx + dx, 1, W - 2), y)
				terr[idx(p)] = "w"
				hgt[idx(p)] = 0
			if rng.randf() < 0.35:
				rx = clamp(rx + rng.randi_range(-1, 1), 3, W - 5)
	# road from west to east
	var ry := H / 2 + rng.randi_range(-1, 1)
	var road: Array = []
	var x := 0
	var y := ry
	var lasth: int = hgt[idx(Vector2i(0, ry))]
	while x < W:
		var p := Vector2i(x, y)
		road.append(p)
		var ch := t(p)
		terr[idx(p)] = "b" if ch == "w" else "r"
		if ch == "w":
			hgt[idx(p)] = 0
		elif abs(h(p) - lasth) > 1:
			hgt[idx(p)] = lasth + sign(h(p) - lasth)
		lasth = h(p)
		if rng.randf() < 0.28 and x > 0 and x < W - 1 and t(Vector2i(x + 1, y)) != "w" and t(p) != "b":
			var ny: int = clamp(y + (1 if rng.randf() < 0.5 else -1), 1, H - 2)
			if ny != y:
				y = ny
				continue
		x += 1
	var road_end: Vector2i = road[road.size() - 1]
	# objectives
	match String(m["type"]):
		"defend":
			goal = Vector2i(2, road[0].y)
			for rp in road:
				if rp.x == 2:
					goal = rp
					break
			set_tile(goal, "V", h(goal))
			for d in [Vector2i(0, -1), Vector2i(0, 1)]:
				var q: Vector2i = goal + d
				if inb(q) and t(q) != "r":
					set_tile(q, "F", h(goal))
		"seize":
			goal = Vector2i(W - 2, road_end.y)
			set_tile(goal, "T", max(1, h(goal)))
			for d in DIRS:
				var q: Vector2i = goal + d
				if inb(q):
					set_tile(q, "F" if d.x == 0 else "r", h(goal))
		"escort":
			for dy in [-1, 0, 1]:
				var q := Vector2i(W - 1, clamp(road_end.y + dy, 0, H - 1))
				set_tile(q, "E", h(road_end))
				exits.append(q)
		_:
			for i in 2:
				var q := Vector2i(rng.randi_range(4, W - 3), rng.randi_range(1, H - 2))
				if t(q) == "g" or t(q) == "f":
					set_tile(q, "F", h(q))
	# spawns
	pspawn = []
	var cand: Array = []
	for yy in H:
		for xx in 3:
			cand.append(Vector2i(xx, yy))
	cand.sort_custom(func(a, b): return abs(a.y - road[0].y) + a.x * 0.6 < abs(b.y - road[0].y) + b.x * 0.6)
	for p in cand:
		if pspawn.size() >= 7:
			break
		if p == goal:
			continue
		if not passable_t(p):
			set_tile(p, "g", h(p))
		pspawn.append(p)
	espawn = []
	var ec: Array = []
	var x0 := W - 5 if m["type"] != "escort" else 7
	for yy in H:
		for xx in range(x0, W):
			var p := Vector2i(xx, yy)
			if p != goal and not exits.has(p) and not pspawn.has(p):
				ec.append(p)
	ec.shuffle()
	ec.sort_custom(func(a, b): return passable_t(a) and not passable_t(b))
	for p in ec:
		if not passable_t(p):
			set_tile(p, "g", h(p))
		espawn.append(p)
	_ensure_connected()

func set_tile(p: Vector2i, ch: String, hh: int) -> void:
	terr[idx(p)] = ch
	hgt[idx(p)] = hh

func _flood(from: Vector2i, jump: int) -> Dictionary:
	var seen := {from: 0}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in DIRS:
			var n: Vector2i = c + d
			if not inb(n) or seen.has(n) or not passable_t(n):
				continue
			var dh := h(n) - h(c)
			if dh > jump or dh < -(jump + 2):
				continue
			seen[n] = int(seen[c]) + int(D.TERRAIN[t(n)]["cost"])
			q.append(n)
	return seen

func _ensure_connected() -> void:
	var need: Array = espawn.slice(0, 14)
	if goal.x >= 0:
		need.append(goal)
	need.append_array(exits)
	need.append_array(pspawn)
	for tries in 40:
		var reach := _flood(pspawn[0], 1)
		var bad: Vector2i = Vector2i(-1, -1)
		for p in need:
			if not reach.has(p):
				bad = p
				break
		if bad.x < 0:
			return
		# carve toward the closest reachable tile
		var best: Vector2i = pspawn[0]
		var bd := 999
		for p in reach:
			var dd: int = abs(p.x - bad.x) + abs(p.y - bad.y)
			if dd < bd:
				bd = dd
				best = p
		var c: Vector2i = best
		while c != bad:
			var step := Vector2i(sign(bad.x - c.x), 0) if c.x != bad.x else Vector2i(0, sign(bad.y - c.y))
			var n: Vector2i = c + step
			if not passable_t(n):
				set_tile(n, "b" if t(n) == "w" else "g", h(n))
			if abs(h(n) - h(c)) > 1:
				hgt[idx(n)] = h(c) + sign(h(n) - h(c))
			c = n

# ================================================================ queries
func idx(p: Vector2i) -> int:
	return p.y * W + p.x

func inb(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H

func t(p: Vector2i) -> String:
	return terr[idx(p)]

func h(p: Vector2i) -> int:
	return hgt[idx(p)]

func tinfo(p: Vector2i) -> Dictionary:
	return D.TERRAIN[t(p)]

func passable_t(p: Vector2i) -> bool:
	return inb(p) and D.TERRAIN[t(p)]["pass"]

func unit_at(p: Vector2i):
	for u in units:
		if u.alive and u.pos == p:
			return u
	return null

func get_unit(id: int):
	for u in units:
		if u.id == id:
			return u
	return null

func team_units(team: int) -> Array:
	var out := []
	for u in units:
		if u.alive and u.team == team:
			out.append(u)
	return out

func dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func stat(u: Unit, k: String) -> int:
	var v := 0
	if k == "mov":
		v = u.mov - (2 if u.status.has("slow") else 0)
		return max(0, v)
	v = int(u.st[k])
	if u.status.has("guard") and (k == "def" or k == "res"):
		v += 4
	if u.status.has("weaken") and (k == "str" or k == "mag"):
		v -= 3
	return max(0, v)

func wpn(u: Unit) -> Dictionary:
	return D.WEAPONS[u.weapon]

## Dijkstra over the grid. Returns {tile: [cost, parent]} for tiles the unit may pass through.
func reach(u: Unit) -> Dictionary:
	var res := {u.pos: [0, u.pos]}
	var open: Array = [u.pos]
	var mv := stat(u, "mov")
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if res[open[i]][0] < res[open[bi]][0]:
				bi = i
		var c: Vector2i = open[bi]
		open.remove_at(bi)
		for d in DIRS:
			var n: Vector2i = c + d
			if not passable_t(n):
				continue
			var dh := h(n) - h(c)
			if dh > u.jump or dh < -(u.jump + 2):
				continue
			var o = unit_at(n)
			if o != null and o.team != u.team:
				continue
			var cost: int = int(res[c][0]) + int(tinfo(n)["cost"]) + (1 if dh >= 2 else 0)
			if cost > mv:
				continue
			if not res.has(n) or int(res[n][0]) > cost:
				res[n] = [cost, c]
				open.append(n)
	return res

func move_tiles(u: Unit) -> Array:
	var out := []
	if u.moved:
		return [u.pos]
	var r := reach(u)
	for p in r:
		var o = unit_at(p)
		if o == null or o == u:
			out.append(p)
	return out

func path_to(u: Unit, dest: Vector2i, r: Dictionary = {}) -> Array:
	if r.is_empty():
		r = reach(u)
	if not r.has(dest):
		return []
	var path := [dest]
	var c := dest
	while c != u.pos:
		c = r[c][1]
		path.push_front(c)
	return path

func abil_info(aid: String) -> Dictionary:
	return D.ABIL[aid] if D.ABIL.has(aid) else {}

func ranges(u: Unit, aid: String) -> Array:
	if aid == "":
		var w := wpn(u)
		return [int(w["r"][0]), int(w["r"][1])]
	var a: Dictionary = D.ABIL[aid]
	return [int(a["r"][0]), int(a["r"][1])]

func can_attack(u: Unit) -> bool:
	return u.weapon != "none" and not u.npc

func ability_ready(u: Unit, aid: String) -> bool:
	return u.abil.has(aid) and int(u.cds.get(aid, 0)) <= 0

func _range_ok(u: Unit, from: Vector2i, tp: Vector2i, aid: String) -> bool:
	var rr := ranges(u, aid)
	var d := dist(from, tp)
	var bonus := 0
	var wt: String = wpn(u)["type"]
	if (wt == "bow" or wt == "bolt") and h(from) - h(tp) >= 2 and rr[1] >= 2:
		bonus = 1
	return d >= rr[0] and d <= rr[1] + bonus

func area(aid: String, center: Vector2i) -> Array:
	var a := abil_info(aid)
	var rad: int = int(a.get("aoe", 0))
	var out := []
	for y in range(-rad, rad + 1):
		for x in range(-rad, rad + 1):
			var p := center + Vector2i(x, y)
			if abs(x) + abs(y) <= rad and inb(p):
				out.append(p)
	return out

## Valid target tiles for an action from a standing tile.
func targets(u: Unit, from: Vector2i, aid: String) -> Array:
	var out := []
	var a := abil_info(aid)
	var kind: String = a.get("kind", "attack")
	if aid == "" and not can_attack(u):
		return out
	if aid != "" and not ability_ready(u, aid):
		return out
	if kind == "attack":
		if a.get("line", false):
			for d in DIRS:
				for k in range(1, 5):
					var p: Vector2i = from + d * k
					if not inb(p):
						break
					var o = unit_at(p)
					if o != null and o != u:
						if o.team != u.team and k >= 2:
							out.append(p)
						break
					if not passable_t(p) or abs(h(p) - h(p - d)) > 1:
						break
			return out
		if int(a.get("aoe", 0)) > 0:
			for y in H:
				for x in W:
					var p := Vector2i(x, y)
					if _range_ok(u, from, p, aid):
						for q in area(aid, p):
							var o = unit_at(q)
							if o != null and o.team != u.team:
								out.append(p)
								break
			return out
		for e in units:
			if not e.alive or e.team == u.team:
				continue
			if not _range_ok(u, from, e.pos, aid):
				continue
			if a.get("step", false) and _behind(e) == Vector2i(-1, -1):
				continue
			out.append(e.pos)
		return out
	if kind == "heal":
		if int(a.get("aoe", 0)) > 0:
			return [from]
		for e in units:
			if e.alive and e.team == u.team and e.hp < e.mhp() and _range_ok(u, from, e.pos, aid) and e != u:
				out.append(e.pos)
		return out
	if kind == "buff" or kind == "debuff":
		return [from]
	if kind == "build" or kind == "summon":
		for d in DIRS:
			var p: Vector2i = from + d
			if passable_t(p) and (unit_at(p) == null or unit_at(p) == u and false) and p != goal and not exits.has(p):
				if unit_at(p) == null:
					out.append(p)
	return out

func _behind(e: Unit) -> Vector2i:
	var p: Vector2i = e.pos - DIRS[e.facing]
	if passable_t(p) and unit_at(p) == null:
		return p
	return Vector2i(-1, -1)

func face_toward(u: Unit, p: Vector2i) -> void:
	var v := p - u.pos
	if v == Vector2i.ZERO:
		return
	if abs(v.x) >= abs(v.y):
		u.facing = 0 if v.x > 0 else 2
	else:
		u.facing = 1 if v.y > 0 else 3

func face_nearest_enemy(u: Unit) -> void:
	var best = null
	var bd := 999
	for e in units:
		if e.alive and e.team != u.team:
			var d := dist(e.pos, u.pos)
			if d < bd:
				bd = d
				best = e
	if best != null:
		face_toward(u, best.pos)

## Combat math. apos = where the attacker strikes from.
func calc(a: Unit, d: Unit, aid: String, apos: Vector2i) -> Dictionary:
	var w := wpn(a)
	var ab := abil_info(aid)
	var magic: bool = w.get("magic", false) or ab.get("magic", false)
	var atk := (stat(a, "mag") if magic else stat(a, "str")) + int(w["mt"])
	var dp := d.pos
	var defv := (stat(d, "res") if magic else stat(d, "def")) + int(tinfo(dp)["def"])
	var mult: float = ab.get("pow", 1.0)
	var hit := int(w["hit"]) + stat(a, "skl") * 2 + int(ab.get("hit", 0)) - (stat(d, "spd") * 2 + int(tinfo(dp)["avo"]))
	var crit := stat(a, "skl") / 2 + int(w["crit"]) + int(ab.get("crit", 0))
	var notes := []
	var ga: String = D.TRI_GROUP.get(w["type"], "")
	var gd: String = D.TRI_GROUP.get(wpn(d)["type"], "")
	if ga != "" and gd != "":
		if D.TRI_BEATS[ga] == gd:
			mult *= 1.15
			hit += 15
			notes.append("Triangle +")
		elif D.TRI_BEATS[gd] == ga:
			mult *= 0.85
			hit -= 15
			notes.append("Triangle -")
	var dh: int = clamp(h(apos) - h(dp), -2, 3)
	if dh != 0:
		mult *= 1.0 + 0.1 * dh
		hit += 5 * dh
		notes.append("High ground" if dh > 0 else "Low ground")
	var v := apos - dp
	var f: Vector2i = DIRS[d.facing]
	var dot := v.x * f.x + v.y * f.y
	if ab.get("step", false) or dot < 0:
		mult *= 2.0 if a.cls == "rogue" else 1.5
		crit += 20
		notes.append("Backstab")
	elif dot == 0 or (abs(v.x) > 0 and abs(v.y) > 0 and abs(dot) < max(abs(v.x), abs(v.y))):
		mult *= 1.2
		hit += 10
		notes.append("Flank")
	if dist(apos, dp) > 1:
		var step := Vector2i(sign(v.x), 0) if abs(v.x) >= abs(v.y) else Vector2i(0, sign(v.y))
		var n: Vector2i = dp + step
		if inb(n) and tinfo(n).get("cover", false) or tinfo(dp).get("cover", false):
			hit -= 20
			notes.append("Cover")
	if int(ab.get("aoe", 0)) > 0:
		hit = 100
	if aid == "charge":
		mult *= 1.0 + 0.1 * dist(apos, dp)
	var dmg: int = max(1, int(round(atk * mult)) - defv) if atk > 0 else 0
	return {"dmg": dmg, "hit": clamp(hit, 5, 100), "crit": clamp(crit, 0, 100), "notes": notes, "magic": magic}

func can_counter(d: Unit, a: Unit, apos: Vector2i, aid: String) -> bool:
	if not d.alive or not can_attack(d) or d.cls == "turret" and false:
		return false
	if abil_info(aid).get("nocounter", false) or abil_info(aid).get("step", false):
		return false
	var w := wpn(d)
	var dd := dist(d.pos, apos)
	return dd >= int(w["r"][0]) and dd <= int(w["r"][1]) + (1 if (w["type"] == "bow" or w["type"] == "bolt") and h(d.pos) - h(apos) >= 2 else 0)

func doubles(a: Unit, d: Unit) -> bool:
	return stat(a, "spd") >= stat(d, "spd") + 5

## Forecast for the UI: attacker strikes d from apos with aid.
func forecast(a: Unit, d: Unit, aid: String, apos: Vector2i) -> Dictionary:
	var f := calc(a, d, aid, apos)
	f["double"] = doubles(a, d) and aid == ""
	var save := a.pos
	a.pos = apos
	f["counter"] = null
	if can_counter(d, a, apos, aid):
		var c := calc(d, a, "", d.pos)
		c["double"] = doubles(d, a)
		f["counter"] = c
	a.pos = save
	return f

# ================================================================ actions
func do_move(u: Unit, dest: Vector2i) -> Array:
	var path := path_to(u, dest)
	if path.is_empty():
		return []
	if path.size() >= 2:
		var last: Vector2i = path[path.size() - 1] - path[path.size() - 2]
		u.facing = DIRS.find(last)
	u.pos = dest
	u.moved = true
	return path

func do_wait(u: Unit) -> void:
	u.moved = true
	u.acted = true
	if u.team == 1 or true:
		face_nearest_enemy(u)

## Executes an action and returns animation events.
func act(u: Unit, aid: String, tp: Vector2i) -> Array:
	var ev: Array = []
	var a := abil_info(aid)
	var kind: String = a.get("kind", "attack")
	if aid != "":
		u.cds[aid] = int(a.get("cd", 0)) + 1
		ev.append({"t": "text", "p": u.pos, "s": a["name"], "c": "abil"})
	match kind:
		"attack":
			if a.get("line", false):
				var dv := Vector2i(sign(tp.x - u.pos.x), sign(tp.y - u.pos.y))
				var stand := tp - dv
				var path := []
				var c := u.pos
				while c != stand:
					c += dv
					path.append(c)
				var start := u.pos
				if stand != u.pos:
					u.pos = stand
					ev.append({"t": "move", "u": u.id, "path": [start] + path})
				u.facing = DIRS.find(dv)
				var e = unit_at(tp)
				if e != null:
					_exchange(u, e, aid, ev, dist(start, tp))
			elif a.get("step", false):
				var e = unit_at(tp)
				var b := _behind(e)
				if b.x >= 0:
					ev.append({"t": "move", "u": u.id, "path": [u.pos, b], "blink": true})
					u.pos = b
				face_toward(u, e.pos)
				_exchange(u, e, aid, ev)
			elif int(a.get("aoe", 0)) > 0:
				face_toward(u, tp)
				ev.append({"t": "blast", "p": tp, "r": int(a["aoe"]), "magic": a.get("magic", false)})
				for q in area(aid, tp):
					var e = unit_at(q)
					if e != null and e.team != u.team and e.alive:
						_strike(u, e, aid, ev, u.pos)
			else:
				var e = unit_at(tp)
				if e == null:
					return ev
				face_toward(u, e.pos)
				_exchange(u, e, aid, ev)
		"heal":
			var amt: int = int(a.get("amt", 8)) + stat(u, "mag") + int(wpn(u).get("heal", 0))
			var list: Array = []
			if int(a.get("aoe", 0)) > 0:
				for o in team_units(u.team):
					if dist(o.pos, u.pos) <= int(a["aoe"]):
						list.append(o)
			else:
				var o = unit_at(tp)
				if o != null:
					list.append(o)
			var healed := 0
			for o in list:
				var before: int = o.hp
				o.hp = min(o.mhp(), o.hp + amt)
				o.status.erase("poison")
				o.status.erase("slow")
				healed += o.hp - before
				ev.append({"t": "heal", "u": o.id, "amt": o.hp - before})
			_gain(u, 12 if healed > 0 else 4, ev)
		"buff":
			for o in team_units(u.team):
				if dist(o.pos, u.pos) <= int(a.get("aoe", 0)):
					o.status[a["status"]] = int(a["turns"]) + 1
					ev.append({"t": "status", "u": o.id, "s": a["status"]})
			_gain(u, 8, ev)
		"debuff":
			for o in units:
				if o.alive and o.team != u.team and dist(o.pos, u.pos) <= int(a.get("aoe", 0)):
					o.status[a["status"]] = int(a["turns"]) + 1
					ev.append({"t": "status", "u": o.id, "s": a["status"]})
			_gain(u, 8, ev)
		"build":
			set_tile(tp, "B", h(tp))
			ev.append({"t": "build", "p": tp})
			_gain(u, 8, ev)
		"summon":
			var r := Game.make_unit(D.CLASSES[a["unit"]]["name"], a["unit"], max(1, u.lvl))
			var s := Unit.new()
			_init_unit(s, r, u.team)
			s.summon = true
			s.pos = tp
			s.moved = true
			s.acted = true
			face_toward(s, tp + (tp - u.pos))
			add_unit(s)
			ev.append({"t": "spawn", "u": s.id})
			_gain(u, 8, ev)
	u.moved = true
	u.acted = true
	check_result()
	return ev

func _exchange(a: Unit, d: Unit, aid: String, ev: Array, dist_bonus: int = 0) -> void:
	var apos := a.pos
	_strike(a, d, aid, ev, apos)
	var ab := abil_info(aid)
	if d.alive and ab.get("push", 0) and a.alive:
		var dv := d.pos - a.pos
		dv = Vector2i(sign(dv.x), sign(dv.y))
		var dest := d.pos + dv
		if passable_t(dest) and unit_at(dest) == null and h(dest) - h(d.pos) <= 1:
			ev.append({"t": "move", "u": d.id, "path": [d.pos, dest], "push": true})
			d.pos = dest
		else:
			d.hp = max(0, d.hp - 3)
			ev.append({"t": "text", "p": d.pos, "s": "Slam! -3", "c": "dmg"})
			if d.hp <= 0:
				_kill(a, d, ev)
	if d.alive and ab.get("pierce", false):
		var dv := Vector2i(sign(d.pos.x - a.pos.x), sign(d.pos.y - a.pos.y))
		var o = unit_at(d.pos + dv)
		if o != null and o.team != a.team:
			_strike(a, o, aid, ev, apos)
	if d.alive and a.alive and can_counter(d, a, apos, aid):
		_strike(d, a, "", ev, d.pos)
	if d.alive and a.alive and doubles(a, d) and aid == "":
		_strike(a, d, "", ev, apos)
	elif d.alive and a.alive and doubles(d, a) and can_counter(d, a, apos, aid):
		_strike(d, a, "", ev, d.pos)

func _strike(a: Unit, d: Unit, aid: String, ev: Array, apos: Vector2i) -> void:
	var f := calc(a, d, aid, apos)
	var hit := rng.randi_range(1, 100) <= int(f["hit"])
	var crit := hit and rng.randi_range(1, 100) <= int(f["crit"])
	var dmg: int = int(f["dmg"]) * (3 if crit else 1) if hit else 0
	if hit:
		d.hp = max(0, d.hp - dmg)
	ev.append({"t": "attack", "a": a.id, "d": d.id, "hit": hit, "crit": crit, "dmg": dmg, "magic": f["magic"], "notes": f["notes"]})
	var ab := abil_info(aid)
	if hit and d.hp > 0 and ab.has("status"):
		d.status[ab["status"]] = int(ab["turns"]) + 1
		ev.append({"t": "status", "u": d.id, "s": ab["status"]})
	if d.hp <= 0:
		_kill(a, d, ev)
	else:
		_gain(a, _xp_for(a, d, 10) if hit else 2, ev)

func _xp_for(a: Unit, d: Unit, base: int) -> int:
	return clamp(base + 3 * (d.lvl - a.lvl), 3, 40)

func _kill(a: Unit, d: Unit, ev: Array) -> void:
	d.alive = false
	d.hp = 0
	ev.append({"t": "die", "u": d.id})
	if d.team == 1:
		kills += 1
		a.kills += 1
	elif not d.summon and not d.npc:
		fallen.append(d.name)
	_gain(a, _xp_for(a, d, 30) + (40 if d.boss else 0), ev)

func _gain(u: Unit, amt: int, ev: Array) -> void:
	if u.team != 0 or u.summon or u.npc or u.ref == null or not u.alive:
		return
	if u.lvl >= 20:
		return
	u.xp += amt
	var info := {"t": "xp", "u": u.id, "amt": amt, "lv": {}}
	while u.xp >= 100 and u.lvl < 20:
		u.xp -= 100
		var gains := Game.level_up(u.ref)
		u.lvl = int(u.ref["lvl"])
		for k in gains:
			u.st[k] = int(u.st[k]) + int(gains[k])
			if k == "hp":
				u.hp += int(gains[k])
		info["lv"] = gains
	u.ref["xp"] = u.xp
	ev.append(info)

# ================================================================ phases & objectives
## Starts a phase for team; returns events (poison, healing, reinforcements).
func start_phase(team: int) -> Array:
	var ev: Array = []
	phase = team
	if team == 0:
		turn += 1
		if m["type"] == "defend" and turn > int(m.get("turns", 6)):
			result = "win"
			return ev
	if team == 1:
		for wv in m.get("waves", []):
			if int(wv[0]) == turn and not waves_done.has(turn):
				waves_done[turn] = true
				for e in wv[1]:
					for i in int(e[2]):
						var p := _free_edge_tile()
						if p.x >= 0:
							var u := spawn_enemy(String(e[0]), int(e[1]), String(e[3]), p)
							ev.append({"t": "spawn", "u": u.id, "wave": true})
	for u in units.duplicate():
		if not u.alive or u.team != team:
			continue
		u.moved = false
		u.acted = false
		for k in u.cds.keys():
			u.cds[k] = max(0, int(u.cds[k]) - 1)
		if u.status.has("poison"):
			var pd: int = min(3, u.hp - 1)
			if pd > 0:
				u.hp -= pd
				ev.append({"t": "text", "p": u.pos, "s": "Poison -%d" % pd, "c": "dmg"})
		var hl: int = int(tinfo(u.pos).get("heal", 0))
		if hl > 0 and u.hp < u.mhp():
			var amt: int = min(u.mhp() - u.hp, max(1, u.mhp() * hl / 100))
			u.hp += amt
			ev.append({"t": "heal", "u": u.id, "amt": amt})
		for k in u.status.keys():
			u.status[k] = int(u.status[k]) - 1
			if int(u.status[k]) <= 0:
				u.status.erase(k)
	_build_danger(team)
	check_result()
	return ev

func _free_edge_tile() -> Vector2i:
	var c: Array = []
	for y in H:
		for x in range(W - 2, W):
			var p := Vector2i(x, y)
			if passable_t(p) and unit_at(p) == null and p != goal:
				c.append(p)
	if c.is_empty():
		return Vector2i(-1, -1)
	return c[rng.randi_range(0, c.size() - 1)]

func phase_done(team: int) -> bool:
	for u in team_units(team):
		if not u.acted:
			return false
	return true

func objective_text() -> String:
	match String(m["type"]):
		"rout": return "Rout the enemy" + (" (or defeat the boss)" if _has_boss() else "")
		"defend": return "Hold the gate for %d turns (turn %d/%d)" % [int(m["turns"]), min(turn, int(m["turns"])), int(m["turns"])]
		"escort": return "Escort the envoy to the east exit"
		"seize": return "Aldric must seize the throne"
	return ""

func _has_boss() -> bool:
	for u in units:
		if u.boss:
			return true
	return false

func check_result() -> String:
	if result != "":
		return result
	var lord_alive := false
	var npc_alive := true
	var any_player := false
	for u in units:
		if u.team == 0 and u.lord and u.alive:
			lord_alive = true
		if u.team == 0 and u.npc and not u.alive:
			npc_alive = false
		if u.team == 0 and u.alive and not u.summon:
			any_player = true
	if not lord_alive or not npc_alive or not any_player:
		result = "lose"
		return result
	var enemies := team_units(1)
	match String(m["type"]):
		"rout":
			var boss_dead := false
			for u in units:
				if u.boss and not u.alive:
					boss_dead = true
			if enemies.is_empty() or boss_dead:
				result = "win"
		"defend":
			for e in enemies:
				if e.pos == goal:
					result = "lose"
			if enemies.is_empty() and turn >= 3 and waves_done.size() >= m.get("waves", []).size():
				result = "win"
		"seize":
			for u in team_units(0):
				if u.lord and u.pos == goal:
					result = "win"
			if enemies.is_empty():
				result = "win"
		"escort":
			for u in team_units(0):
				if u.npc and exits.has(u.pos):
					result = "win"
	return result

# ================================================================ AI
func _build_danger(team: int = 1) -> void:
	danger = {}
	for p in team_units(1 - team):
		if not can_attack(p):
			continue
		var rr := ranges(p, "")
		var mt := move_tiles(p) if true else []
		var hits := {}
		for s in mt:
			for y in range(-rr[1] - 1, rr[1] + 2):
				for x in range(-rr[1] - 1, rr[1] + 2):
					var q: Vector2i = s + Vector2i(x, y)
					var d: int = abs(x) + abs(y)
					if inb(q) and d >= rr[0] and d <= rr[1]:
						hits[q] = true
		for q in hits:
			danger[q] = int(danger.get(q, 0)) + 1

## Chooses the best move + action for an AI-controlled unit.
func ai_plan(u: Unit) -> Dictionary:
	var best := {"move": u.pos, "aid": "", "target": null, "score": -9999.0}
	var r := reach(u)
	var tiles: Array = []
	for p in r:
		var o = unit_at(p)
		if o == null or o == u:
			tiles.append(p)
	if u.ai == "guard" or u.cls == "turret":
		var near := false
		for p in team_units(1 - u.team):
			if dist(p.pos, u.start) <= u.mov + 3:
				near = true
		if u.boss and m["type"] == "seize" or not near or u.cls == "turret":
			tiles = [u.pos]
	var acts: Array = [""]
	for aid in u.abil:
		var k: String = abil_info(aid).get("kind", "")
		if ability_ready(u, aid) and (k == "attack" or k == "heal"):
			acts.append(aid)
	var hpr := float(u.hp) / u.mhp()
	for mt in tiles:
		var ts := _tile_score(u, mt, hpr)
		for aid in acts:
			var kind: String = abil_info(aid).get("kind", "attack")
			for tp in targets(u, mt, aid):
				var s := ts
				if kind == "heal":
					var tot := 0
					if int(abil_info(aid).get("aoe", 0)) > 0:
						for o in team_units(u.team):
							if dist(o.pos, mt) <= int(abil_info(aid)["aoe"]):
								tot += o.mhp() - o.hp
					else:
						var o = unit_at(tp)
						tot = o.mhp() - o.hp
					if tot < 4:
						continue
					s += tot * 2.0
				else:
					s += _attack_score(u, mt, aid, tp)
				if s > best["score"]:
					best = {"move": mt, "aid": aid, "target": tp, "score": s}
	if u.team == 0 and u.lord and m["type"] == "seize" and tiles.has(goal):
		return {"move": goal, "aid": "", "target": null, "score": 999.0}
	if u.team == 0 and u.npc:
		for e in exits:
			if tiles.has(e):
				return {"move": e, "aid": "", "target": null, "score": 999.0}
	if best["target"] != null:
		return best
	# no target: advance toward the objective / weakest reachable foe, using cover
	if tiles.size() <= 1:
		return {"move": u.pos, "aid": "", "target": null, "score": 0.0}
	var dest := _ai_destination(u)
	var fl := _flood(dest, u.jump)
	var bt: Vector2i = u.pos
	var bs := -9999.0
	for mt in tiles:
		var dd: float = float(fl.get(mt, 60))
		var s := -dd * 3.0 + _tile_score(u, mt, hpr) * 0.6
		if s > bs:
			bs = s
			bt = mt
	return {"move": bt, "aid": "", "target": null, "score": bs}

func _tile_score(u: Unit, p: Vector2i, hpr: float) -> float:
	var ti := tinfo(p)
	var s := float(ti["def"]) * 3.0 + float(ti["avo"]) / 5.0 + h(p) * 1.5
	for d in DIRS:
		var n: Vector2i = p + d
		if inb(n) and tinfo(n).get("cover", false):
			s += 1.5
	s -= float(danger.get(p, 0)) * (6.0 if hpr < 0.5 or (u.lord and u.team == 0) else 2.0)
	return s

func _attack_score(u: Unit, mt: Vector2i, aid: String, tp: Vector2i) -> float:
	var s := 0.0
	var list: Array = []
	if int(abil_info(aid).get("aoe", 0)) > 0:
		for q in area(aid, tp):
			var o = unit_at(q)
			if o != null and o.team != u.team:
				list.append(o)
		if list.size() < 2 and aid != "":
			s -= 10.0
	else:
		var o = unit_at(tp)
		if o != null:
			list.append(o)
	var save := u.pos
	u.pos = mt
	for d in list:
		var f := forecast(u, d, aid, mt)
		var exp: float = float(f["dmg"]) * float(f["hit"]) / 100.0 * (2.0 if f["double"] else 1.0)
		s += exp * 2.0
		if float(f["dmg"]) * (2 if f["double"] else 1) >= d.hp and int(f["hit"]) >= 45:
			s += 60.0 + (30.0 if d.lord else 0.0) + (40.0 if d.npc else 0.0)
		s += 25.0 * (1.0 - float(d.hp) / d.mhp())
		if d.cls in ["healer", "mage", "archer"] or d.npc:
			s += 10.0
		if d.npc:
			s += 25.0
		if f["notes"].has("Backstab"):
			s += 8.0
		if f["counter"] != null:
			var c: Dictionary = f["counter"]
			s -= float(c["dmg"]) * float(c["hit"]) / 100.0 * 1.2
	u.pos = save
	return s

func _ai_destination(u: Unit) -> Vector2i:
	if m["type"] == "defend" and (u.ai == "goal" or u.team == 0):
		return goal
	if u.team == 0 and u.npc and not exits.is_empty():
		return exits[1]
	if u.team == 0 and u.lord and m["type"] == "seize":
		return goal
	var best: Vector2i = u.pos
	var bs := -9999.0
	for p in team_units(1 - u.team):
		var s: float = -float(dist(p.pos, u.pos)) - float(p.hp) / p.mhp() * 4.0 + (8.0 if p.npc else 0.0)
		if s > bs:
			bs = s
			best = p.pos
	return best

## Runs one AI unit's whole turn instantly (used by tests and auto-play). Returns events.
func ai_turn(u: Unit) -> Array:
	var plan := ai_plan(u)
	var ev: Array = []
	if plan["move"] != u.pos:
		var path := do_move(u, plan["move"])
		ev.append({"t": "move", "u": u.id, "path": path})
	if plan["target"] != null:
		ev.append_array(act(u, plan["aid"], plan["target"]))
	else:
		do_wait(u)
	check_result()
	return ev
