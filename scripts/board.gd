extends Node2D
## Isometric board renderer + pointer input. All art is drawn in code.

signal tile_tapped(p: Vector2i)
signal tile_hovered(p: Vector2i)

const TW := 64.0
const TH := 32.0
const HZ := 13.0
const TEAM_COL := [Color("3f74d8"), Color("c8443c")]
const NPC_COL := Color("47a565")
const SKIN := [Color("f1c9a0"), Color("d9a77c"), Color("a8714a"), Color("7a4e2e")]

var b: Battle = null
var interactive := true
var vis := {}            # uid -> {"p": Vector2 grid, "a": alpha, "fl": flash, "bump": Vector2}
var move_set: Array = []
var atk_set: Array = []
var abil_set: Array = []
var area_set: Array = []
var path_set: Array = []
var cursor := Vector2i(-1, -1)
var selected_id := -1
var floaters: Array = []
var parts: Array = []
var shake := 0.0
var time := 0.0
var user_zoom := 1.0
var pan := Vector2.ZERO
var base_pos := Vector2.ZERO
var base_scale := 1.0
var _press := false
var _press_pos := Vector2.ZERO
var _dragged := false
var _last_mouse := Vector2.ZERO
var fit_rect := Rect2(0, 0, 1280, 720)

func setup(battle: Battle) -> void:
	b = battle
	vis = {}
	for u in b.units:
		sync_unit(u)
	queue_redraw()

func sync_unit(u) -> void:
	if not vis.has(u.id):
		vis[u.id] = {"p": Vector2(u.pos), "a": 1.0, "fl": 0.0, "bump": Vector2.ZERO, "hp": float(u.hp)}
	vis[u.id]["p"] = Vector2(u.pos)

# ---------------------------------------------------------------- geometry
func iso(gx: float, gy: float, hh: float) -> Vector2:
	return Vector2((gx - gy) * TW * 0.5, (gx + gy) * TH * 0.5 - hh * HZ)

func tile_center(p: Vector2i) -> Vector2:
	return iso(p.x, p.y, _th(p))

func _th(p: Vector2i) -> float:
	var hh := float(b.h(p))
	if b.t(p) == "w":
		hh = -0.35
	return hh

func board_bounds() -> Rect2:
	var r := Rect2(iso(0, 0, 3), Vector2.ZERO)
	for p in [Vector2i(0, 0), Vector2i(Battle.W - 1, 0), Vector2i(0, Battle.H - 1), Vector2i(Battle.W - 1, Battle.H - 1)]:
		r = r.expand(iso(p.x, p.y, 0) + Vector2(0, TH * 0.5 + 12))
		r = r.expand(iso(p.x, p.y, 3.5) - Vector2(0, TH * 0.5 + 40))
		r = r.expand(iso(p.x, p.y, 0) + Vector2(TW * 0.5, 0))
		r = r.expand(iso(p.x, p.y, 0) - Vector2(TW * 0.5, 0))
	return r

func fit(rect: Rect2) -> void:
	fit_rect = rect
	var bb := board_bounds()
	var sx := rect.size.x / bb.size.x
	if rect.size.y > rect.size.x * 1.1:
		sx *= 1.45
	base_scale = clamp(min(sx, rect.size.y / bb.size.y), 0.3, 1.8)
	base_pos = rect.get_center() - bb.get_center() * base_scale
	_apply_xform()

func _apply_xform() -> void:
	scale = Vector2.ONE * base_scale * user_zoom
	var center := fit_rect.get_center()
	position = center + (base_pos - center) * user_zoom + pan + Vector2(randf_range(-shake, shake), randf_range(-shake, shake))

func zoom_by(f: float) -> void:
	user_zoom = clamp(user_zoom * f, 0.7, 2.6)
	if user_zoom <= 1.0:
		pan = pan * 0.5
	_apply_xform()

func pick(screen_pos: Vector2) -> Vector2i:
	var lp := to_local(screen_pos)
	var best := Vector2i(-1, -1)
	var order := _order()
	for i in range(order.size() - 1, -1, -1):
		var p: Vector2i = order[i]
		var c := tile_center(p)
		var d := lp - c
		if abs(d.x) / (TW * 0.5) + abs(d.y) / (TH * 0.5) <= 1.0:
			return p
	# fall back to the column below the pointer (side faces)
	for i in range(order.size() - 1, -1, -1):
		var p: Vector2i = order[i]
		var c := tile_center(p)
		var d := lp - c
		if abs(d.x) <= TW * 0.25 and d.y >= 0 and d.y <= (_th(p) + 0.5) * HZ:
			return p
	return best

func _order() -> Array:
	var out: Array = []
	for s in range(Battle.W + Battle.H - 1):
		for x in range(Battle.W):
			var y := s - x
			if y >= 0 and y < Battle.H:
				out.append(Vector2i(x, y))
	return out

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if b == null or not interactive or not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = true
				_dragged = false
				_press_pos = mb.position
				_last_mouse = mb.position
			elif _press:
				_press = false
				if not _dragged:
					var p := pick(mb.position)
					if p.x >= 0:
						cursor = p
						tile_tapped.emit(p)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press:
			if mm.position.distance_to(_press_pos) > 14.0:
				_dragged = true
			if _dragged:
				pan += mm.position - _last_mouse
				var lim := fit_rect.size * 0.6 * user_zoom
				pan = pan.clamp(-lim, lim)
				_apply_xform()
			_last_mouse = mm.position
		else:
			var p := pick(mm.position)
			if p != cursor:
				cursor = p
				if p.x >= 0:
					tile_hovered.emit(p)

# ---------------------------------------------------------------- fx
func float_text(p: Vector2, s: String, col: Color, big: bool = false) -> void:
	floaters.append({"p": p, "s": s, "c": col, "t": 0.0, "big": big})

func burst(p: Vector2, col: Color, n: int = 14, spd: float = 120.0) -> void:
	for i in n:
		var a := randf() * TAU
		parts.append({"p": p, "v": Vector2(cos(a), sin(a) * 0.6 - 0.5) * randf_range(spd * 0.3, spd), "t": 0.0, "life": randf_range(0.35, 0.7), "c": col, "s": randf_range(2.0, 4.5)})

func unit_screen(uid: int) -> Vector2:
	if not vis.has(uid):
		return Vector2.ZERO
	var gp: Vector2 = vis[uid]["p"]
	var tp := Vector2i(clamp(int(round(gp.x)), 0, Battle.W - 1), clamp(int(round(gp.y)), 0, Battle.H - 1))
	return iso(gp.x, gp.y, _th(tp)) + vis[uid]["bump"]

func _process(delta: float) -> void:
	time += delta
	if shake > 0.0:
		shake = max(0.0, shake - delta * 22.0)
		_apply_xform()
	for f in floaters:
		f["t"] += delta
	floaters = floaters.filter(func(f): return f["t"] < 1.1)
	for q in parts:
		q["t"] += delta
		q["p"] += q["v"] * delta
		q["v"].y += 260.0 * delta
	parts = parts.filter(func(q): return q["t"] < q["life"])
	for id in vis:
		var v: Dictionary = vis[id]
		v["fl"] = max(0.0, v["fl"] - delta * 3.0)
		var u = b.get_unit(id) if b != null else null
		if u != null:
			v["hp"] = move_toward(v["hp"], float(u.hp), delta * 40.0)
			if not u.alive:
				v["a"] = max(0.0, v["a"] - delta * 1.6)
	queue_redraw()

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if b == null:
		return
	var order := _order()
	for p in order:
		_draw_tile(p)
	for p in order:
		_draw_overlay(p)
	var us: Array = []
	for u in b.units:
		if vis.has(u.id) and (u.alive or vis[u.id]["a"] > 0.0):
			us.append(u)
	us.sort_custom(func(a, c): return vis[a.id]["p"].x + vis[a.id]["p"].y < vis[c.id]["p"].x + vis[c.id]["p"].y)
	for u in us:
		_draw_unit(u)
	for q in parts:
		var k: float = 1.0 - q["t"] / q["life"]
		draw_circle(q["p"], q["s"] * k + 0.5, Color(q["c"], k))
	var font := ThemeDB.fallback_font
	for f in floaters:
		var k: float = f["t"]
		var pos: Vector2 = f["p"] + Vector2(0, -40 - k * 38.0)
		var sz := 26 if f["big"] else 18
		var a: float = clamp(1.6 - k * 1.5, 0.0, 1.0)
		var w := font.get_string_size(f["s"], HORIZONTAL_ALIGNMENT_CENTER, -1, sz).x
		draw_string_outline(font, pos - Vector2(w * 0.5, 0), f["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6, Color(0, 0, 0, a))
		draw_string(font, pos - Vector2(w * 0.5, 0), f["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(f["c"], a))

func _tcol(p: Vector2i) -> Color:
	var ch := b.t(p)
	var n := float((p.x * 7 + p.y * 13) % 5) / 5.0
	match ch:
		"g": return Color("5f9a48").lerp(Color("6fae52"), n)
		"f": return Color("3f7a3a").lerp(Color("4a8a40"), n)
		"r": return Color("b89a6a").lerp(Color("c4a878"), n)
		"s": return Color("6f7a45").lerp(Color("7a8350"), n)
		"w": return Color("2f6fb0").lerp(Color("3a80c4"), 0.5 + 0.5 * sin(time * 2.0 + p.x + p.y * 0.7))
		"x": return Color("7d7b80").lerp(Color("8c8a90"), n)
		"b": return Color("8a5f38")
		"F": return Color("8e8a86")
		"T": return Color("a08a5a")
		"V": return Color("9a7a50")
		"E": return Color("d8c06a")
		"B": return Color("6f5638")
	return Color.MAGENTA

func _draw_tile(p: Vector2i) -> void:
	var hh := _th(p)
	var c := iso(p.x, p.y, hh)
	var hw := TW * 0.5
	var hh2 := TH * 0.5
	var top := PackedVector2Array([c + Vector2(0, -hh2), c + Vector2(hw, 0), c + Vector2(0, hh2), c + Vector2(-hw, 0)])
	var col := _tcol(p)
	var depth: float = (hh + 1.0) * HZ
	var side := Color("4b3b2c") if b.t(p) != "w" else Color("24507e")
	if b.t(p) in ["g", "f", "s"] and hh >= 1:
		side = Color("6a5038")
	var left := PackedVector2Array([c + Vector2(-hw, 0), c + Vector2(0, hh2), c + Vector2(0, hh2 + depth), c + Vector2(-hw, depth)])
	var right := PackedVector2Array([c + Vector2(0, hh2), c + Vector2(hw, 0), c + Vector2(hw, depth), c + Vector2(0, hh2 + depth)])
	draw_colored_polygon(left, side.darkened(0.15))
	draw_colored_polygon(right, side.darkened(0.38))
	# strata lines on tall columns
	for k in range(1, int(hh) + 1):
		var y := k * HZ
		draw_line(c + Vector2(-hw, y), c + Vector2(0, hh2 + y), Color(0, 0, 0, 0.12), 1.0)
		draw_line(c + Vector2(0, hh2 + y), c + Vector2(hw, y), Color(0, 0, 0, 0.12), 1.0)
	draw_colored_polygon(top, col)
	draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), Color(0, 0, 0, 0.16), 1.0)
	_draw_feature(p, c)

func _draw_feature(p: Vector2i, c: Vector2) -> void:
	var ch := b.t(p)
	var r := (p.x * 31 + p.y * 17) % 7
	match ch:
		"g":
			if r < 3:
				for i in 3:
					var o := Vector2((i - 1) * 9 + r, (i % 2) * 4 - 2)
					draw_line(c + o, c + o + Vector2(-2, -5), Color("3f7a30"), 1.5)
					draw_line(c + o, c + o + Vector2(2, -6), Color("4c8c38"), 1.5)
		"f":
			for o in [Vector2(-12, -2), Vector2(10, 1), Vector2(-1, 6)]:
				var tp: Vector2 = c + o
				draw_rect(Rect2(tp + Vector2(-2, -6), Vector2(4, 8)), Color("5a3a22"))
				draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -30), tp + Vector2(10, -6), tp + Vector2(-10, -6)]), Color("2c5e2c"))
				draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -36), tp + Vector2(7, -18), tp + Vector2(-7, -18)]), Color("3b7a36"))
		"x":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-18, 4), c + Vector2(-10, -16), c + Vector2(4, -20), c + Vector2(16, -6), c + Vector2(14, 6), c + Vector2(-6, 10)]), Color("6a686e"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -16), c + Vector2(4, -20), c + Vector2(16, -6), c + Vector2(0, -6)]), Color("a2a0a6"))
		"b":
			for i in 4:
				var o := Vector2(-18 + i * 12, -9 + i * 6)
				draw_line(c + o + Vector2(-6, -3), c + o + Vector2(12, 6) - Vector2(10, 5) + Vector2(6, 3), Color("5c3c20"), 2.0)
			draw_line(c + Vector2(-26, -4), c + Vector2(6, 12), Color("4a2e18"), 2.0)
			draw_line(c + Vector2(-6, -12), c + Vector2(26, 4), Color("4a2e18"), 2.0)
		"F":
			for o in [Vector2(-20, -2), Vector2(0, -12), Vector2(20, -2), Vector2(0, 8)]:
				draw_rect(Rect2(c + o + Vector2(-4, -10), Vector2(8, 10)), Color("6d6862"))
				draw_rect(Rect2(c + o + Vector2(-4, -10), Vector2(8, 3)), Color("b0aaa2"))
		"T":
			draw_rect(Rect2(c + Vector2(-9, -26), Vector2(18, 24)), Color("6b2a2a"))
			draw_rect(Rect2(c + Vector2(-11, -8), Vector2(22, 8)), Color("d9a441"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -26), c + Vector2(-5, -34), c + Vector2(0, -27), c + Vector2(5, -34), c + Vector2(9, -26)]), Color("d9a441"))
			_banner(c + Vector2(16, -2), Color("d9a441"))
		"V":
			draw_rect(Rect2(c + Vector2(-16, -30), Vector2(6, 30)), Color("5c3c20"))
			draw_rect(Rect2(c + Vector2(10, -30), Vector2(6, 30)), Color("5c3c20"))
			draw_rect(Rect2(c + Vector2(-16, -34), Vector2(32, 6)), Color("7a5230"))
			_banner(c + Vector2(0, -34), Color("3f74d8"))
		"E":
			var k := 0.5 + 0.5 * sin(time * 3.0)
			draw_arc(c, 10.0 + k * 6.0, 0, TAU, 20, Color(1, 0.95, 0.6, 0.6), 2.0)
			_banner(c + Vector2(0, -4), Color("47a565"))
		"B":
			for i in 3:
				var o := Vector2(-14 + i * 14, -i * 2)
				draw_line(c + o + Vector2(0, 6), c + o + Vector2(-4, -18), Color("8a6238"), 4.0)
				draw_line(c + o + Vector2(-4, -18), c + o + Vector2(-2, -24), Color("c9a070"), 3.0)
			draw_line(c + Vector2(-20, -4), c + Vector2(20, -8), Color("5c3c20"), 3.0)

func _banner(base: Vector2, col: Color) -> void:
	draw_line(base, base + Vector2(0, -36), Color("3a2a1a"), 2.0)
	var w := sin(time * 4.0) * 2.0
	draw_colored_polygon(PackedVector2Array([base + Vector2(0, -36), base + Vector2(16, -32 + w), base + Vector2(0, -26)]), col)

func _diamond(p: Vector2i, col: Color, inset: float = 2.0, outline: bool = false) -> void:
	var c := tile_center(p)
	var hw := TW * 0.5 - inset
	var hh := TH * 0.5 - inset * 0.5
	var pts := PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0)])
	if outline:
		pts.append(pts[0])
		draw_polyline(pts, col, 2.5)
	else:
		draw_colored_polygon(pts, col)

func _draw_overlay(p: Vector2i) -> void:
	var pulse := 0.75 + 0.25 * sin(time * 5.0)
	if move_set.has(p):
		_diamond(p, Color(0.3, 0.6, 1.0, 0.38 * pulse))
		_diamond(p, Color(0.6, 0.85, 1.0, 0.6), 3.0, true)
	if atk_set.has(p):
		_diamond(p, Color(1.0, 0.25, 0.2, 0.42 * pulse))
		_diamond(p, Color(1.0, 0.6, 0.5, 0.7), 3.0, true)
	if abil_set.has(p):
		_diamond(p, Color(0.75, 0.4, 1.0, 0.42 * pulse))
		_diamond(p, Color(0.9, 0.7, 1.0, 0.7), 3.0, true)
	if area_set.has(p):
		_diamond(p, Color(1.0, 0.8, 0.2, 0.45))
	if path_set.has(p):
		draw_circle(tile_center(p), 4.0, Color(1, 1, 1, 0.8))
	if p == b.goal and b.goal.x >= 0:
		_diamond(p, Color(1.0, 0.85, 0.3, 0.5 + 0.3 * sin(time * 3.0)), 4.0, true)
	if p == cursor:
		_diamond(p, Color(1, 0.95, 0.5, 0.95), 1.0, true)

func _draw_unit(u) -> void:
	var v: Dictionary = vis[u.id]
	var at := unit_screen(u.id)
	var alpha: float = v["a"]
	var exhausted: bool = u.acted and u.team == b.phase and u.alive
	var team_c: Color = NPC_COL if u.npc else TEAM_COL[u.team]
	var mod := Color(1, 1, 1, alpha)
	if exhausted:
		mod = Color(0.6, 0.6, 0.65, alpha)
	var fl: float = v["fl"]
	# facing: screen x direction
	var fd: Vector2i = Battle.DIRS[u.facing]
	var sx := 1.0 if (fd == Vector2i(1, 0) or fd == Vector2i(0, -1)) else -1.0
	var back := fd == Vector2i(0, -1) or fd == Vector2i(-1, 0)
	# ground: shadow + facing arrow + selection ring
	_ellipse(at + Vector2(0, 2), 16, 6, Color(0, 0, 0, 0.3 * alpha))
	var fv := iso(fd.x, fd.y, 0) * 0.42
	draw_colored_polygon(PackedVector2Array([at + fv, at + fv * 0.55 + fv.orthogonal().normalized() * 5.0, at + fv * 0.55 - fv.orthogonal().normalized() * 5.0]), Color(team_c.lightened(0.3), 0.8 * alpha))
	if u.id == selected_id:
		_ellipse_line(at + Vector2(0, 2), 20 + sin(time * 6.0) * 2.0, 8, Color(1, 0.9, 0.4, alpha))
	var bob := sin(time * 3.0 + u.id) * 1.2 if u.alive and not exhausted else 0.0
	var o := at + Vector2(0, bob)
	if u.cls == "wolf":
		_draw_wolf(o, sx, mod, team_c, fl)
	elif u.cls == "turret":
		_draw_turret(o, sx, mod, team_c, fl)
	else:
		_draw_person(u, o, sx, back, mod, team_c, fl)
	# HP bar
	var top := o + Vector2(0, -50)
	var frac: float = clamp(v["hp"] / max(1.0, float(u.mhp())), 0.0, 1.0)
	if alpha > 0.05:
		draw_rect(Rect2(top + Vector2(-15, 0), Vector2(30, 5)), Color(0, 0, 0, 0.7 * alpha))
		var hc := Color("5ad06a") if frac > 0.5 else (Color("e8c040") if frac > 0.25 else Color("e04a3a"))
		draw_rect(Rect2(top + Vector2(-14, 1), Vector2(28 * frac, 3)), Color(hc, alpha))
		var si := 0
		for s in u.status:
			var sc: Color = {"guard": Color("8fc0ff"), "slow": Color("7fe0ff"), "poison": Color("a050d0"), "weaken": Color("ff9040")}.get(s, Color.WHITE)
			draw_circle(top + Vector2(-12 + si * 7, -5), 3.0, Color(sc, alpha))
			si += 1
	if u.boss:
		var cp := o + Vector2(0, -60)
		draw_colored_polygon(PackedVector2Array([cp + Vector2(-8, 4), cp + Vector2(-8, -4), cp + Vector2(-4, 0), cp + Vector2(0, -6), cp + Vector2(4, 0), cp + Vector2(8, -4), cp + Vector2(8, 4)]), Color("ffd24a", alpha))
	if u.lord:
		draw_circle(o + Vector2(0, -60), 3.5, Color("ffd24a", alpha))

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _ellipse_line(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, 2.0)

func _m(c: Color, mod: Color, fl: float) -> Color:
	var r := Color(c.r * mod.r, c.g * mod.g, c.b * mod.b, c.a * mod.a)
	return r.lerp(Color(1, 1, 1, r.a), fl)

func _draw_person(u, o: Vector2, sx: float, back: bool, mod: Color, team_c: Color, fl: float) -> void:
	var cls: String = u.cls
	var skin: Color = SKIN[(u.id * 3 + 1) % SKIN.size()]
	var dark := team_c.darkened(0.45)
	var robe := cls in ["mage", "healer", "envoy"]
	var body_c := team_c
	match cls:
		"healer": body_c = Color("ece6d6") if u.team == 0 else Color("c9b8b0")
		"rogue": body_c = team_c.darkened(0.35)
		"mage": body_c = team_c.lerp(Color("7a3fb0"), 0.45)
		"beastmaster": body_c = team_c.lerp(Color("7a5230"), 0.4)
		"engineer": body_c = team_c.lerp(Color("b07a3a"), 0.35)
	# legs
	if not robe:
		draw_rect(Rect2(o + Vector2(-6, -12), Vector2(5, 12)), _m(dark, mod, fl))
		draw_rect(Rect2(o + Vector2(1, -12), Vector2(5, 12)), _m(dark, mod, fl))
	# body
	var bw := 11.0 if cls != "knight" else 13.0
	var body := PackedVector2Array([o + Vector2(-bw, -12 if not robe else 0), o + Vector2(bw, -12 if not robe else 0), o + Vector2(bw * 0.7, -32), o + Vector2(-bw * 0.7, -32)])
	draw_colored_polygon(body, _m(body_c, mod, fl))
	draw_rect(Rect2(o + Vector2(-bw * 0.8, -16), Vector2(bw * 1.6, 3)), _m(dark.lightened(0.2), mod, fl))
	if cls == "healer":
		draw_rect(Rect2(o + Vector2(-1.5, -28), Vector2(3, 12)), _m(Color("d03a3a"), mod, fl))
		draw_rect(Rect2(o + Vector2(-5, -24), Vector2(10, 3)), _m(Color("d03a3a"), mod, fl))
	if cls == "beastmaster":
		_ellipse(o + Vector2(0, -31), 13, 5, _m(Color("8a6a48"), mod, fl))
	# head
	var hp := o + Vector2(0, -38)
	draw_circle(hp, 7.0, _m(skin, mod, fl))
	if not back:
		draw_circle(hp + Vector2(sx * 3.0, -1), 1.2, _m(Color(0.1, 0.1, 0.1), mod, fl))
	# headgear
	match cls:
		"knight":
			draw_colored_polygon(PackedVector2Array([hp + Vector2(-8, 2), hp + Vector2(-8, -4), hp + Vector2(-4, -9), hp + Vector2(4, -9), hp + Vector2(8, -4), hp + Vector2(8, 2)]), _m(Color("b8bcc8"), mod, fl))
			draw_line(hp + Vector2(sx * 1, -1), hp + Vector2(sx * 8, -1), _m(Color("30323a"), mod, fl), 2.0)
			draw_line(hp + Vector2(0, -9), hp + Vector2(-sx * 6, -16), _m(Color("d03a3a") if u.team == 0 else Color("2a2a2a"), mod, fl), 4.0)
		"lancer":
			draw_colored_polygon(PackedVector2Array([hp + Vector2(-7, -2), hp + Vector2(0, -12), hp + Vector2(7, -2)]), _m(Color("a8acb8"), mod, fl))
		"archer":
			draw_colored_polygon(PackedVector2Array([hp + Vector2(-8, -2), hp + Vector2(0, -10), hp + Vector2(8, -2)]), _m(Color("3f7a3a"), mod, fl))
			draw_line(hp + Vector2(-sx * 2, -7), hp + Vector2(-sx * 10, -14), _m(Color("e04a3a"), mod, fl), 2.0)
		"mage":
			draw_colored_polygon(PackedVector2Array([hp + Vector2(-10, -2), hp + Vector2(-sx * 3, -24), hp + Vector2(10, -2)]), _m(Color("4a2a7a"), mod, fl))
			draw_rect(Rect2(hp + Vector2(-10, -4), Vector2(20, 3)), _m(Color("d9a441"), mod, fl))
		"healer":
			draw_arc(hp, 8.0, PI, TAU, 10, _m(Color("f4f0e6"), mod, fl), 4.0)
		"rogue":
			draw_arc(hp, 7.5, PI * 0.9, TAU + 0.2, 12, _m(Color("2a2430"), mod, fl), 5.0)
			draw_line(hp + Vector2(-6, 2), hp + Vector2(6, 2), _m(Color("2a2430"), mod, fl), 3.0)
		"engineer":
			draw_circle(hp + Vector2(sx * 2, -3), 2.6, _m(Color("e8c040"), mod, fl))
			draw_circle(hp + Vector2(sx * 7, -3), 2.2, _m(Color("e8c040"), mod, fl))
			draw_arc(hp, 7.5, PI, TAU, 10, _m(Color("6a4a2a"), mod, fl), 3.0)
		"beastmaster":
			draw_arc(hp, 8.0, PI * 1.1, TAU - 0.3, 10, _m(Color("7a5a3a"), mod, fl), 4.0)
			draw_colored_polygon(PackedVector2Array([hp + Vector2(-8, -5), hp + Vector2(-6, -13), hp + Vector2(-3, -7)]), _m(Color("e8e0d0"), mod, fl))
			draw_colored_polygon(PackedVector2Array([hp + Vector2(8, -5), hp + Vector2(6, -13), hp + Vector2(3, -7)]), _m(Color("e8e0d0"), mod, fl))
		"envoy":
			draw_rect(Rect2(hp + Vector2(-9, -8), Vector2(18, 3)), _m(Color("2a5a3a"), mod, fl))
			draw_rect(Rect2(hp + Vector2(-5, -14), Vector2(10, 7)), _m(Color("2a5a3a"), mod, fl))
	# weapon in front hand
	var hand := o + Vector2(sx * 12, -20)
	var steel := _m(Color("dfe3ea"), mod, fl)
	var wood := _m(Color("7a5230"), mod, fl)
	match cls:
		"knight":
			draw_line(hand, hand + Vector2(sx * 6, -18), steel, 3.0)
			draw_line(hand + Vector2(sx * -2, -2), hand + Vector2(sx * 6, 2), _m(Color("d9a441"), mod, fl), 2.0)
			draw_rect(Rect2(o + Vector2(-sx * 16 - 5, -28), Vector2(10, 14)), _m(team_c.lightened(0.2), mod, fl))
			draw_rect(Rect2(o + Vector2(-sx * 16 - 1.5, -26), Vector2(3, 10)), _m(Color("d9a441"), mod, fl))
		"lancer":
			draw_line(hand + Vector2(-sx * 8, 10), hand + Vector2(sx * 10, -30), wood, 2.5)
			draw_colored_polygon(PackedVector2Array([hand + Vector2(sx * 10, -30), hand + Vector2(sx * 15, -42), hand + Vector2(sx * 6, -33)]), steel)
		"archer":
			draw_arc(hand + Vector2(sx * 2, -4), 13.0, -PI * 0.5 - 1.1 if sx > 0 else PI * 0.5 - 1.1, -PI * 0.5 + 1.1 if sx > 0 else PI * 0.5 + 1.1, 10, wood, 2.5)
			draw_line(hand + Vector2(sx * 2, -4) + Vector2(sx * 13, 0).rotated(-1.1 * sx), hand + Vector2(sx * 2, -4) + Vector2(sx * 13, 0).rotated(1.1 * sx), Color(1, 1, 1, 0.6 * mod.a), 1.0)
		"mage":
			draw_rect(Rect2(hand + Vector2(-5, -6), Vector2(10, 9)), _m(Color("7a2a2a"), mod, fl))
			draw_circle(hand + Vector2(0, -12), 3.0 + sin(time * 6.0), Color(1.0, 0.6, 0.2, 0.8 * mod.a))
		"healer":
			draw_line(hand + Vector2(0, 14), hand + Vector2(0, -22), wood, 2.5)
			draw_arc(hand + Vector2(0, -25), 4.0, 0, TAU, 10, _m(Color("e8d070"), mod, fl), 2.0)
		"rogue":
			draw_line(hand, hand + Vector2(sx * 9, -7), steel, 2.5)
			draw_line(o + Vector2(-sx * 12, -20), o + Vector2(-sx * 18, -26), steel, 2.0)
		"engineer":
			draw_line(hand + Vector2(0, 6), hand + Vector2(sx * 4, -16), wood, 3.0)
			draw_rect(Rect2(hand + Vector2(sx * 4 - 6, -22), Vector2(12, 7)), _m(Color("8a8e98"), mod, fl))
		"beastmaster":
			draw_line(hand + Vector2(0, 6), hand + Vector2(sx * 4, -18), wood, 3.0)
			draw_colored_polygon(PackedVector2Array([hand + Vector2(sx * 4, -18), hand + Vector2(sx * 14, -22), hand + Vector2(sx * 12, -10), hand + Vector2(sx * 3, -12)]), steel)

func _draw_wolf(o: Vector2, sx: float, mod: Color, team_c: Color, fl: float) -> void:
	var fur := _m(Color("8a8f9a"), mod, fl)
	_ellipse(o + Vector2(0, -12), 14, 7, fur)
	for lx in [-9, -4, 5, 10]:
		draw_rect(Rect2(o + Vector2(lx - 1.5, -8), Vector2(3, 8)), _m(Color("5a5e68"), mod, fl))
	var hp := o + Vector2(sx * 13, -18)
	draw_circle(hp, 6.0, fur)
	draw_colored_polygon(PackedVector2Array([hp + Vector2(sx * 4, -1), hp + Vector2(sx * 11, 2), hp + Vector2(sx * 4, 4)]), fur)
	draw_colored_polygon(PackedVector2Array([hp + Vector2(-3, -4), hp + Vector2(-1, -12), hp + Vector2(2, -4)]), fur)
	draw_line(o + Vector2(-sx * 13, -14), o + Vector2(-sx * 20, -22), fur, 3.0)
	draw_rect(Rect2(o + Vector2(sx * 6 - 5, -17), Vector2(10, 3)), _m(team_c, mod, fl))

func _draw_turret(o: Vector2, sx: float, mod: Color, team_c: Color, fl: float) -> void:
	draw_line(o + Vector2(-10, 0), o + Vector2(0, -16), _m(Color("6a4a2a"), mod, fl), 3.0)
	draw_line(o + Vector2(10, 0), o + Vector2(0, -16), _m(Color("6a4a2a"), mod, fl), 3.0)
	draw_rect(Rect2(o + Vector2(-9, -26), Vector2(18, 10)), _m(team_c, mod, fl))
	draw_line(o + Vector2(0, -21), o + Vector2(sx * 18, -24), _m(Color("8a8e98"), mod, fl), 3.0)
	draw_arc(o + Vector2(sx * 14, -23), 8.0, -1.2, 1.2, 8, _m(Color("6a4a2a"), mod, fl), 2.0)
