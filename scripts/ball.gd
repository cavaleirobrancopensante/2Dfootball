class_name Ball
extends Node2D
## The ball. `position` is its spot on the grass; `z` is its height above it.
## Bounces off the boards around the pitch (arcade rules: no throw-ins),
## except through the goal mouths.

signal goal(side: int)        # side 0 = left goal, 1 = right goal
signal bounced(strength: float)

const RADIUS := 7.0
const GRAVITY := 980.0
const GROUND_FRICTION := 1.7
const AIR_DRAG := 0.25
const CROSSBAR := 46.0

var pitch: Rect2
var goal_half_width := 130.0
var goal_depth := 46.0

var velocity := Vector2.ZERO
var z := 0.0
var vz := 0.0
var owner_player: Node2D = null   # the Footballer dribbling it, if any
var last_touch_team := -1
var in_goal := false
var _spin := 0.0


func _physics_process(delta: float) -> void:
	if owner_player != null:
		return   # the dribbler positions the ball
	_spin += velocity.length() * delta * 0.08 * signf(velocity.x + 0.001)

	# Height
	if z > 0.0 or vz > 0.0:
		vz -= GRAVITY * delta
		z += vz * delta
		if z <= 0.0:
			z = 0.0
			if vz < -120.0:
				bounced.emit(-vz)
				vz = -vz * 0.45
			else:
				vz = 0.0
	# Friction
	if z <= 0.5:
		velocity *= maxf(0.0, 1.0 - GROUND_FRICTION * delta)
	else:
		velocity *= maxf(0.0, 1.0 - AIR_DRAG * delta)
	if velocity.length() < 4.0:
		velocity = Vector2.ZERO

	var prev := position
	position += velocity * delta
	_collide(prev)


func _collide(prev: Vector2) -> void:
	var cy := pitch.get_center().y
	var mouth := absf(position.y - cy) < goal_half_width - RADIUS
	# Goal line crossings
	if not in_goal:
		if position.x < pitch.position.x and prev.x >= pitch.position.x and mouth and z < CROSSBAR:
			in_goal = true
			goal.emit(0)
		elif position.x > pitch.end.x and prev.x <= pitch.end.x and mouth and z < CROSSBAR:
			in_goal = true
			goal.emit(1)
	if in_goal:
		# Trapped in the net.
		var back_l := pitch.position.x - goal_depth + RADIUS
		var back_r := pitch.end.x + goal_depth - RADIUS
		if position.x < back_l:
			position.x = back_l; velocity.x = absf(velocity.x) * 0.2
		if position.x > back_r:
			position.x = back_r; velocity.x = -absf(velocity.x) * 0.2
		var lim := goal_half_width - RADIUS
		if absf(position.y - cy) > lim:
			position.y = cy + signf(position.y - cy) * lim
			velocity.y *= -0.3
		z = minf(z, CROSSBAR - 4.0)
		return
	# Boards
	var bounce := 0.6
	if position.y < pitch.position.y + RADIUS:
		position.y = pitch.position.y + RADIUS; velocity.y = absf(velocity.y) * bounce; _hit_board()
	elif position.y > pitch.end.y - RADIUS:
		position.y = pitch.end.y - RADIUS; velocity.y = -absf(velocity.y) * bounce; _hit_board()
	if position.x < pitch.position.x + RADIUS and not (mouth and z < CROSSBAR):
		position.x = pitch.position.x + RADIUS; velocity.x = absf(velocity.x) * bounce; _hit_board()
	elif position.x > pitch.end.x - RADIUS and not (mouth and z < CROSSBAR):
		position.x = pitch.end.x - RADIUS; velocity.x = -absf(velocity.x) * bounce; _hit_board()


func _hit_board() -> void:
	if velocity.length() > 150.0:
		bounced.emit(velocity.length())


## Strike the ball.
func kick(dir: Vector2, speed: float, lift: float, team: int) -> void:
	owner_player = null
	velocity = dir.normalized() * speed
	vz = lift
	z = maxf(z, 1.0)
	last_touch_team = team


func reset_to(p: Vector2) -> void:
	owner_player = null
	in_goal = false
	position = p
	velocity = Vector2.ZERO
	z = 0.0
	vz = 0.0


func is_loose() -> bool:
	return owner_player == null and not in_goal


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Shadow on the grass, ball drawn up at its height.
	var s := clampf(1.0 - z / 200.0, 0.4, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2(2, 2), RADIUS * s, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2(0, -z - RADIUS * 0.6))
	draw_circle(Vector2.ZERO, RADIUS + 1.0, Color(0.08, 0.08, 0.08))
	draw_circle(Vector2.ZERO, RADIUS, Color(0.97, 0.97, 0.95))
	for i in 3:
		var a := _spin + i * TAU / 3.0
		var p := Vector2(cos(a), sin(a) * 0.8) * RADIUS * 0.5
		draw_circle(p, 1.8, Color(0.1, 0.1, 0.1))
	draw_circle(Vector2(-2.5, -2.5), 1.6, Color(1, 1, 1, 0.9))
	draw_set_transform(Vector2.ZERO)
