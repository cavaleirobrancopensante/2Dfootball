class_name Controls
extends Control
## Touch controls: floating joystick on the left, four PlayStation-style
## buttons on the right.
##   ×  PASS    tap = short pass, hold = long ball (bar fills)
##   □  SHOOT   hold to power up, release to shoot
##   ○  CROSS   hold to power up, release to cross
##   △  TACKLE  (slide) when defending / DRIBBLE when your team has the ball:
##              hold = sprint, tap = skill move past a defender
## Desktop: WASD/arrows to move, J = ×, K = □, L = ○, I = △ (Space also shoots).
## The mouse works as a touch (project setting).

signal button_down(button: String)
signal button_up(button: String, held: float)
signal pause_pressed

const STICK_RADIUS := 85.0
const BUTTON_RADIUS := 46.0
const BUTTONS := ["pass", "shoot", "cross", "tackle"]
const KEYS := {KEY_J: "pass", KEY_K: "shoot", KEY_SPACE: "shoot", KEY_L: "cross", KEY_I: "tackle"}

var move_vector := Vector2.ZERO
var labels := {"pass": "PASS", "shoot": "SHOOT", "cross": "CROSS", "tackle": "TACKLE"}
var charge := 0.0          # shown on the held button
var charge_button := ""

var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _held := {}            # button -> {"id": touch index or -1 for keyboard, "t": msec}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func center() -> Vector2:
	return Vector2(size.x - 165, size.y - 150)


func button_pos(b: String) -> Vector2:
	var c := center()
	match b:
		"tackle": return c + Vector2(0, -78)
		"cross": return c + Vector2(80, 0)
		"pass": return c + Vector2(0, 78)
		_: return c + Vector2(-80, 0)      # shoot


func pause_rect() -> Rect2:
	return Rect2(14, 12, 56, 46)


func is_held(b: String) -> bool:
	return _held.has(b)


func held_time(b: String) -> float:
	if not _held.has(b):
		return 0.0
	return (Time.get_ticks_msec() - int(_held[b]["t"])) / 1000.0


func _press(b: String, id: int) -> void:
	if _held.has(b):
		return
	_held[b] = {"id": id, "t": Time.get_ticks_msec()}
	button_down.emit(b)


func _release(b: String) -> void:
	if not _held.has(b):
		return
	var t := held_time(b)
	_held.erase(b)
	button_up.emit(b, t)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if pause_rect().grow(10).has_point(e.position):
				pause_pressed.emit()
				return
			for b in BUTTONS:
				if e.position.distance_to(button_pos(b)) < BUTTON_RADIUS + 10:
					_press(b, e.index)
					return
			if e.position.x < size.x * 0.55 and _stick_id == -1:
				_stick_id = e.index
				_stick_origin = e.position
				_stick_pos = e.position
		else:
			if e.index == _stick_id:
				_stick_id = -1
				move_vector = Vector2.ZERO
			for b in _held.keys():
				if int(_held[b]["id"]) == e.index:
					_release(b)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_pos = d.position
			var v := (_stick_pos - _stick_origin) / STICK_RADIUS
			move_vector = Vector2.ZERO if v.length() < 0.18 else v.limit_length(1.0)
	elif event is InputEventKey and not event.is_echo():
		var k := event as InputEventKey
		if KEYS.has(k.keycode):
			var b: String = KEYS[k.keycode]
			if k.pressed:
				_press(b, -1)
			else:
				_release(b)
		elif k.keycode == KEY_ESCAPE and k.pressed:
			pause_pressed.emit()


func get_move() -> Vector2:
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): k.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): k.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): k.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): k.y += 1
	return k.normalized() if k != Vector2.ZERO else move_vector


func reset() -> void:
	_stick_id = -1
	_held.clear()
	move_vector = Vector2.ZERO


func _process(_delta: float) -> void:
	queue_redraw()


const COLORS := {
	"pass": Color(0.35, 0.55, 0.95), "shoot": Color(0.9, 0.45, 0.75),
	"cross": Color(0.95, 0.35, 0.3), "tackle": Color(0.3, 0.8, 0.55),
}


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Pause button
	var pr := pause_rect()
	draw_rect(pr, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(pr.position + Vector2(18, 12), Vector2(7, 22)), Color(1, 1, 1, 0.8))
	draw_rect(Rect2(pr.position + Vector2(31, 12), Vector2(7, 22)), Color(1, 1, 1, 0.8))
	# Joystick
	if _stick_id != -1:
		draw_circle(_stick_origin, STICK_RADIUS, Color(0, 0, 0, 0.25))
		draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(_stick_origin + (_stick_pos - _stick_origin).limit_length(STICK_RADIUS), 34, Color(1, 1, 1, 0.5))
	else:
		var c := Vector2(150, size.y - 140)
		draw_arc(c, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 3.0)
		_label(font, c + Vector2(0, 6), "MOVE", 16, Color(1, 1, 1, 0.3))
	# Buttons
	for b in BUTTONS:
		var p := button_pos(b)
		var col: Color = COLORS[b]
		var held := _held.has(b)
		draw_circle(p, BUTTON_RADIUS, Color(0.05, 0.05, 0.08, 0.55 if held else 0.38))
		draw_arc(p, BUTTON_RADIUS, 0, TAU, 40, Color(col, 0.9), 4.0 if held else 3.0)
		_symbol(b, p + Vector2(0, -10), col)
		_label(font, p + Vector2(0, 26), labels[b], 13, Color(1, 1, 1, 0.9))
		if b == charge_button and charge > 0.0:
			draw_arc(p, BUTTON_RADIUS + 8, -PI / 2, -PI / 2 + TAU * charge, 40, Color(1, 0.9, 0.3), 6.0)


func _symbol(b: String, p: Vector2, col: Color) -> void:
	var w := 3.0
	match b:
		"pass":
			draw_line(p + Vector2(-9, -9), p + Vector2(9, 9), col, w)
			draw_line(p + Vector2(9, -9), p + Vector2(-9, 9), col, w)
		"shoot":
			draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), col, false, w)
		"cross":
			draw_arc(p, 10, 0, TAU, 24, col, w)
		_:
			draw_polyline(PackedVector2Array([p + Vector2(0, -11), p + Vector2(10, 8), p + Vector2(-10, 8), p + Vector2(0, -11)]), col, w)


func _label(font: Font, c: Vector2, s: String, sz: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string_outline(font, c - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.6))
	draw_string(font, c - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
