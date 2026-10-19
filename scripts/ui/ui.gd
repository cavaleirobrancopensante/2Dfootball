class_name UI
## Small helpers for building the manager screens in code, sized for phones.

const BG := Color("#13241a")
const PANEL := Color("#1c3324")
const ACCENT := Color("#3fa45a")
const GOLD := Color("#f0c850")
const MUTED := Color(1, 1, 1, 0.6)
const ROW_H := 46.0


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _box(Color("#24442e"), 8))
	t.set_stylebox("hover", "Button", _box(Color("#2d5639"), 8))
	t.set_stylebox("pressed", "Button", _box(Color("#3a7049"), 8))
	t.set_stylebox("disabled", "Button", _box(Color("#2a2f2c"), 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 10, 14))
	t.set_color("font_color", "Label", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.25)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


static func _box(c: Color, r: int, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func label(text: String, size := 20, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, cb: Callable, size := 22, min_size := Vector2(0, 54)) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = min_size
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func accent_button(text: String, cb: Callable, size := 24, min_size := Vector2(0, 60), col := ACCENT) -> Button:
	var b := button(text, cb, size, min_size)
	b.add_theme_stylebox_override("normal", _box(col, 10))
	b.add_theme_stylebox_override("hover", _box(col.lightened(0.1), 10))
	b.add_theme_stylebox_override("pressed", _box(col.lightened(0.2), 10))
	return b


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.scroll_deadzone = 12
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func panel(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(child)
	return p


static func spacer(h := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A table row. cells: Array of [text, width (0 = expand), align, colour?].
## If cb is valid the row is a tappable button.
static func row(cells: Array, cb := Callable(), tint := Color(0, 0, 0, 0), size := 19) -> Control:
	var h := hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for cell in cells:
		var col: Color = cell[3] if cell.size() > 3 else Color.WHITE
		var l := label(str(cell[0]), size, col, cell[2] if cell.size() > 2 else HORIZONTAL_ALIGNMENT_LEFT)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if float(cell[1]) <= 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = float(cell[1])
		h.add_child(l)
	var holder: Control
	if cb.is_valid():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, ROW_H)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.pressed.connect(cb)
		if tint.a > 0.0:
			b.add_theme_stylebox_override("normal", _box(tint, 6))
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.offset_right = -10
		b.add_child(h)
		holder = b
	else:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(tint if tint.a > 0.0 else Color(0, 0, 0, 0), 6))
		p.custom_minimum_size = Vector2(0, ROW_H - 8)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(h)
		holder = p
	return holder


## Small horizontal bar for ratings / condition.
static func bar(value: float, width := 120.0, col := ACCENT) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 14)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var fg := ColorRect.new()
	fg.color = col
	fg.position = Vector2(1, 1)
	fg.size = Vector2((width - 2) * clampf(value, 0.0, 1.0), 12)
	c.add_child(fg)
	return c


static func rating_colour(v: float) -> Color:
	if v >= 80:
		return Color("#5fd47a")
	if v >= 65:
		return Color("#b5d65a")
	if v >= 50:
		return Color("#e8c050")
	if v >= 35:
		return Color("#e88a40")
	return Color("#e05050")


static func swatch(kit: Dictionary, s := 22.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(s, s)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := ColorRect.new()
	a.color = Color(kit["shirt"])
	a.size = Vector2(s, s * 0.6)
	c.add_child(a)
	var b := ColorRect.new()
	b.color = Color(kit["shorts"])
	b.position = Vector2(0, s * 0.6)
	b.size = Vector2(s, s * 0.4)
	c.add_child(b)
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
