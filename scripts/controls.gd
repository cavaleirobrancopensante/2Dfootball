class_name Controls
extends Control
## Touch controls: a floating joystick on the left half, two buttons on the right.
##   Big button  : SHOOT (hold to power up) with the ball / TACKLE (slide) without
##   Small button: PASS with the ball / SWITCH player without
## Desktop: WASD/arrows to move, K = big button, J = small button.
## The mouse also works as a touch (project setting).

signal shoot_pressed
signal shoot_released
signal pass_pressed

const STICK_RADIUS := 85.0

var move_vector := Vector2.ZERO
var shoot_held := false
var shoot_label := "SHOOT"
var pass_label := "PASS"
var charge := 0.0   # 0..1, shown on the shoot button while holding

var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _shoot_id := -1
var _pass_flash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func shoot_center() -> Vector2:
	return Vector2(size.x - 120, size.y - 120)


func pass_center() -> Vector2:
	return Vector2(size.x - 265, size.y - 85)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if e.position.distance_to(shoot_center()) < 85.0 and _shoot_id == -1:
				_shoot_id = e.index
				shoot_held = true
				shoot_pressed.emit()
			elif e.position.distance_to(pass_center()) < 65.0:
				_pass_flash = 0.15
				pass_pressed.emit()
			elif e.position.x < size.x * 0.55 and _stick_id == -1:
				_stick_id = e.index
				_stick_origin = e.position
				_stick_pos = e.position
		else:
			if e.index == _stick_id:
				_stick_id = -1
				move_vector = Vector2.ZERO
			elif e.index == _shoot_id:
				_shoot_id = -1
				shoot_held = false
				shoot_released.emit()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_pos = d.position
			var v := (_stick_pos - _stick_origin) / STICK_RADIUS
			move_vector = Vector2.ZERO if v.length() < 0.18 else v.limit_length(1.0)
	elif event is InputEventKey and not event.is_echo():
		var k := event as InputEventKey
		if k.keycode == KEY_K or k.keycode == KEY_SPACE:
			if k.pressed and not shoot_held:
				shoot_held = true
				shoot_pressed.emit()
			elif not k.pressed and shoot_held and _shoot_id == -1:
				shoot_held = false
				shoot_released.emit()
		elif k.keycode == KEY_J and k.pressed:
			_pass_flash = 0.15
			pass_pressed.emit()


func get_move() -> Vector2:
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): k.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): k.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): k.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): k.y += 1
	return k.normalized() if k != Vector2.ZERO else move_vector


func reset() -> void:
	_stick_id = -1
	_shoot_id = -1
	move_vector = Vector2.ZERO
	shoot_held = false


func _process(delta: float) -> void:
	_pass_flash = maxf(_pass_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Joystick
	if _stick_id != -1:
		draw_circle(_stick_origin, STICK_RADIUS, Color(0, 0, 0, 0.25))
		draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(_stick_origin + (_stick_pos - _stick_origin).limit_length(STICK_RADIUS), 34, Color(1, 1, 1, 0.5))
	else:
		var c := Vector2(150, size.y - 140)
		draw_arc(c, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 3.0)
		_label(font, c + Vector2(0, 6), "MOVE", 16, Color(1, 1, 1, 0.3))
	# Shoot button
	var sc := shoot_center()
	draw_circle(sc, 72, Color(0.85, 0.2, 0.2, 0.55 if shoot_held else 0.38))
	draw_arc(sc, 72, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0)
	if charge > 0.0:
		draw_arc(sc, 80, -PI / 2, -PI / 2 + TAU * charge, 48, Color(1, 0.9, 0.3), 7.0)
	_label(font, sc + Vector2(0, 8), shoot_label, 22, Color(1, 1, 1, 0.95))
	# Pass button
	var pc := pass_center()
	draw_circle(pc, 54, Color(0.2, 0.5, 0.9, 0.6 if _pass_flash > 0.0 else 0.38))
	draw_arc(pc, 54, 0, TAU, 40, Color(1, 1, 1, 0.6), 3.0)
	_label(font, pc + Vector2(0, 7), pass_label, 18, Color(1, 1, 1, 0.95))


func _label(font: Font, c: Vector2, s: String, sz: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string_outline(font, c - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.6))
	draw_string(font, c - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
