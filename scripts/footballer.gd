class_name Footballer
extends Node2D
## One player on the pitch: movement, animation, recolouring, hair, and the
## physical actions (kick, pass, slide, fall, header, celebrate).
## Decisions are made by Match (AI) or by the human controls.

const RUN_SPEED := 200.0
const DRIBBLE_SPEED := 182.0
const ACCEL := 1100.0
const SLIDE_SPEED := 430.0
const ACTION_TIME := {
	"kick": 0.32, "pass": 0.24, "slide": 0.5, "fall": 0.9, "header": 0.35, "celebrate": 99.0,
}
const RECOLOR := preload("res://shaders/recolor.gdshader")

static var _tex_cache: Dictionary = {}

var team := 0
var number := 1
var is_gk := false
var home := Vector2.ZERO         # formation spot (pitch coordinates)
var pitch: Rect2

var velocity := Vector2.ZERO
var desired := Vector2.ZERO      # desired velocity this frame
var facing := Vector2.RIGHT
var action := ""
var action_t := 0.0
var cooldown := 0.0              # can't touch the ball while > 0 (just kicked/fell)
var controlled := false

var _anim := ""
var _dir := ""
var _flip := false
var _frame_t := 0.0
var _frame := 0
var _hair_style := ""
var _mat: ShaderMaterial

var rig: Node2D
var body: Sprite2D
var hair: Sprite2D


func setup(look: Dictionary, kit: Dictionary, goalkeeper: bool) -> void:
	is_gk = goalkeeper
	_hair_style = look["hair_style"]
	_mat = ShaderMaterial.new()
	_mat.shader = RECOLOR
	_mat.set_shader_parameter("skin", look["skin"])
	_mat.set_shader_parameter("hair", look["hair_colour"])
	var shirt: Color = kit["gk"] if goalkeeper else kit["shirt"]
	_mat.set_shader_parameter("shirt", shirt)
	_mat.set_shader_parameter("shorts", kit["shorts"] if not goalkeeper else shirt.darkened(0.4))
	_mat.set_shader_parameter("socks", kit["socks"] if not goalkeeper else shirt)


func _ready() -> void:
	rig = Node2D.new()
	add_child(rig)
	body = Sprite2D.new()
	body.centered = false
	body.offset = -SpriteData.ANCHOR
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.material = _mat
	rig.add_child(body)
	hair = Sprite2D.new()
	hair.centered = false
	hair.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hair.material = _mat
	hair.visible = _hair_style != ""
	rig.add_child(hair)
	_set_anim("idle", true)


static func tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


# ------------------------------------------------------------------ actions

func busy() -> bool:
	return action != "" and action != "celebrate"


func can_touch_ball() -> bool:
	return cooldown <= 0.0 and action != "fall" and action != "celebrate"


func start_action(a: String) -> void:
	action = a
	action_t = ACTION_TIME[a]
	_frame = 0
	_frame_t = 0.0
	if a == "slide":
		velocity = facing * SLIDE_SPEED
	if a == "fall":
		cooldown = 1.0
		velocity *= 0.3


func stop_action() -> void:
	action = ""


func move_toward_point(target: Vector2, speed_factor := 1.0, arrive := 30.0) -> void:
	var to := target - position
	var d := to.length()
	if d < 4.0:
		desired = Vector2.ZERO
		return
	var spd := RUN_SPEED * speed_factor * clampf(d / arrive, 0.25, 1.0)
	desired = to / d * spd


func face_toward(p: Vector2) -> void:
	var d := p - position
	if d.length() > 1.0:
		facing = d.normalized()


# ------------------------------------------------------------------ update

func _physics_process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	if action != "":
		action_t -= delta
		if action_t <= 0.0:
			action = ""
	match action:
		"slide":
			velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
		"fall":
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		"celebrate":
			velocity = velocity.move_toward(desired * 0.4, ACCEL * delta)
		"kick", "pass", "header":
			velocity = velocity.move_toward(desired * 0.3, ACCEL * delta)
		_:
			velocity = velocity.move_toward(desired, ACCEL * delta)
			if desired.length() > 20.0:
				facing = facing.lerp(desired.normalized(), clampf(12.0 * delta, 0.0, 1.0)).normalized()
	position += velocity * delta
	var margin := 6.0
	position = position.clamp(pitch.position + Vector2(margin, margin), pitch.end - Vector2(margin, margin))
	_animate(delta)
	queue_redraw()


func _animate(delta: float) -> void:
	var anim := "idle"
	if action != "":
		anim = action
	elif velocity.length() > 25.0:
		anim = "run"
	_set_anim(anim, false)
	var n: int = SpriteData.FRAMES[_anim + "_" + _dir]
	var fps := 3.0
	match _anim:
		"run":
			fps = 6.0 + velocity.length() / 22.0
		"idle":
			fps = 2.5
		"celebrate":
			fps = 7.0
		_:
			fps = float(n) / maxf(ACTION_TIME.get(_anim, 0.4), 0.1)
	_frame_t += delta * fps
	if _frame_t >= 1.0:
		_frame_t -= 1.0
		_frame += 1
	var looping := _anim in ["run", "idle", "celebrate"]
	if looping:
		_frame %= n
	else:
		_frame = mini(_frame, n - 1)
	body.frame = _frame
	_place_hair()


func _set_anim(anim: String, force: bool) -> void:
	var dir_flip := _octant()
	var d: String = dir_flip[0]
	var flip: bool = dir_flip[1]
	if not force and anim == _anim and d == _dir and flip == _flip:
		return
	if anim != _anim:
		_frame = 0
		_frame_t = 0.0
	_anim = anim
	_dir = d
	_flip = flip
	var key := anim + "_" + d
	body.texture = tex("res://assets/players/body/%s.png" % key)
	body.hframes = SpriteData.FRAMES[key]
	_frame = mini(_frame, body.hframes - 1)
	rig.scale.x = -1.0 if flip else 1.0
	if _hair_style != "":
		hair.texture = tex("res://assets/players/hair/%s_%s.png" % [_hair_style, d])


func _place_hair() -> void:
	if _hair_style == "":
		return
	var heads: Array = SpriteData.HEADS[_anim + "_" + _dir]
	var h: Vector3 = heads[mini(_frame, heads.size() - 1)]
	var a: Vector2 = SpriteData.HAIR_ANCHOR[_hair_style + "_" + _dir]
	hair.position = Vector2(h.x, h.y) - a


## Sheet has s, se, e, ne, n; the west-facing ones are mirrored.
func _octant() -> Array:
	var o := int(round(facing.angle() / (PI / 4.0)))
	o = posmod(o, 8)
	match o:
		0: return ["e", false]
		1: return ["se", false]
		2: return ["s", false]
		3: return ["se", true]
		4: return ["e", true]
		5: return ["ne", true]
		6: return ["n", false]
		_: return ["ne", false]


## Where the ball sits when this player dribbles it.
func dribble_point() -> Vector2:
	return position + facing * 15.0 + Vector2(0, 2)


func _draw() -> void:
	# Shadow, and a ring under the player you control.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.25))
	if controlled:
		draw_arc(Vector2.ZERO, 22.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 3.0)
	draw_set_transform(Vector2.ZERO)
	if controlled:
		var t := Vector2(0, -82)
		draw_colored_polygon(PackedVector2Array([t + Vector2(-7, -8), t + Vector2(7, -8), t + Vector2(0, 2)]), Color(1, 1, 0.6))
