class_name UI
## Small helpers for building the code-made interface.

const GOLD := Color("e0b552")
const INK := Color("f1e8d2")
const DIM := Color("b3a58c")
const PANEL := Color("231c2b")
const EDGE := Color("8a6a35")
const RED := Color("e0584a")
const GREEN := Color("6fd07a")
const BLUE := Color("7fb2ff")

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var sb := func(bg: Color, edge: Color, bw: int = 2) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = edge
		s.set_border_width_all(bw)
		s.set_corner_radius_all(6)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 7
		s.content_margin_bottom = 7
		return s
	t.set_stylebox("normal", "Button", sb.call(Color("3a2c22"), EDGE))
	t.set_stylebox("hover", "Button", sb.call(Color("4e3a28"), GOLD))
	t.set_stylebox("pressed", "Button", sb.call(Color("2a1f18"), GOLD))
	t.set_stylebox("disabled", "Button", sb.call(Color("2a2428"), Color("4a4048")))
	t.set_stylebox("focus", "Button", sb.call(Color(0, 0, 0, 0), Color(1, 0.85, 0.4, 0.6)))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color("fff4d6"))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("7a7068"))
	t.set_stylebox("panel", "PanelContainer", sb.call(Color(PANEL, 0.94), EDGE))
	t.set_stylebox("panel", "Panel", sb.call(Color(PANEL, 0.94), EDGE))
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0))
	t.set_constant("outline_size", "Label", 0)
	t.set_color("default_color", "RichTextLabel", INK)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color("8a6a35")
	sc.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sc)
	t.set_stylebox("grabber_highlight", "VScrollBar", sc)
	var tr := StyleBoxFlat.new()
	tr.bg_color = Color(0, 0, 0, 0.3)
	tr.content_margin_left = 6
	tr.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", tr)
	return t

static func btn(text: String, cb: Callable, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 42)
	b.pressed.connect(func():
		Sfx.play("select")
		cb.call())
	return b

static func lbl(text: String, size: int = 18, col: Color = INK, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func rich(bb: String, size: int = 17) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	return p

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

static func centered(child: Control, max_w: float = 640.0) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	child.custom_minimum_size.x = max_w
	cc.add_child(child)
	return cc

static func hexc(c: Color) -> String:
	return c.to_html(false)
