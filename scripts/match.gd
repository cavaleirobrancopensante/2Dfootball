extends Node2D
## Runs a 5-a-side match: you (team 0, attacking right) against the computer.
## States: menu -> kickoff -> play -> goal -> kickoff ... -> fulltime -> menu.

const PITCH := Rect2(0, 0, 2200, 1300)
const GOAL_HALF := 130.0
const MATCH_SECONDS := 180.0
const SAVE_PATH := "user://record.save"

# Formation for a team attacking to the right, as fractions of the pitch.
const FORMATION := [
	Vector2(0.035, 0.5),   # keeper
	Vector2(0.22, 0.30),   # defenders
	Vector2(0.22, 0.70),
	Vector2(0.40, 0.38),   # forwards
	Vector2(0.44, 0.62),
]

var version: String = ProjectSettings.get_setting("application/config/version", "dev")
var rng := RandomNumberGenerator.new()

var world: Node2D
var ball: Ball
var camera: Camera2D
var controls: Controls
var hud: Control
var teams: Array = [[], []]       # Array of Array[Footballer]
var kit_index := [0, 1]
var score := [0, 0]
var record := {"w": 0, "d": 0, "l": 0}

var state := "menu"
var state_t := 0.0
var clock := MATCH_SECONDS
var kickoff_team := 0
var banner := ""
var banner_t := 0.0

var controlled: Footballer
var autopilot := false   # testing: the computer plays both sides
var _switch_lock := 0.0
var _charging := false
var _charge := 0.0
var receiver: Array = [null, null]   # intended pass receiver per team
var _think: Dictionary = {}          # per-player decision cooldowns
var _carry_t := 0.0                  # how long the current carrier has had it
var _sounds: Dictionary = {}
var _shake := 0.0


func _ready() -> void:
	rng.randomize()
	_load_record()
	var pitch_node := Node2D.new()
	pitch_node.set_script(preload("res://scripts/pitch.gd"))
	pitch_node.set("pitch", PITCH)
	pitch_node.set("goal_half_width", GOAL_HALF)
	pitch_node.z_index = -10
	add_child(pitch_node)

	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)

	ball = Ball.new()
	ball.pitch = PITCH
	ball.goal_half_width = GOAL_HALF
	ball.goal.connect(_on_goal)
	ball.bounced.connect(func(s: float) -> void: _sfx("bounce", linear_to_db(clampf(s / 900.0, 0.05, 1.0))))
	world.add_child(ball)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.92, 0.92)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	var lim := PITCH.grow(200)
	camera.limit_left = int(lim.position.x)
	camera.limit_top = int(lim.position.y)
	camera.limit_right = int(lim.end.x)
	camera.limit_bottom = int(lim.end.y)
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	controls = Controls.new()
	controls.shoot_pressed.connect(_on_shoot_pressed)
	controls.shoot_released.connect(_on_shoot_released)
	controls.pass_pressed.connect(_on_pass_pressed)
	layer.add_child(controls)
	controls.visible = false

	for n in ["kick", "whistle", "cheer", "bounce", "pass"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.wav" % n)
		p.max_polyphony = 3
		add_child(p)
		_sounds[n] = p

	kit_index[1] = Kits.contrasting(kit_index[0], rng)
	_build_teams()
	_place_for_kickoff(0)
	state = "menu"
	camera.position = PITCH.get_center()


func _sfx(n: String, db := 0.0) -> void:
	var p: AudioStreamPlayer = _sounds[n]
	p.volume_db = db
	p.pitch_scale = rng.randf_range(0.94, 1.06)
	p.play()


# ------------------------------------------------------------------ setup

func _build_teams() -> void:
	for t in teams:
		for p in t:
			(p as Node).queue_free()
	teams = [[], []]
	for team in 2:
		var kit: Dictionary = Kits.TEAMS[kit_index[team]]
		for i in FORMATION.size():
			var f := Footballer.new()
			f.team = team
			f.number = i + 1
			f.pitch = PITCH
			f.setup(Kits.random_look(rng), kit, i == 0)
			f.home = _formation_point(team, i)
			world.add_child(f)
			teams[team].append(f)


func _formation_point(team: int, i: int) -> Vector2:
	var fr: Vector2 = FORMATION[i]
	if team == 1:
		fr.x = 1.0 - fr.x
	return PITCH.position + fr * PITCH.size


func _place_for_kickoff(team: int) -> void:
	kickoff_team = team
	ball.reset_to(PITCH.get_center())
	receiver = [null, null]
	for t in 2:
		for i in teams[t].size():
			var p: Footballer = teams[t][i]
			p.position = _formation_point(t, i)
			p.velocity = Vector2.ZERO
			p.desired = Vector2.ZERO
			p.stop_action()
			p.cooldown = 0.0
			p.facing = Vector2.RIGHT if t == 0 else Vector2.LEFT
	var striker: Footballer = teams[team][3]
	striker.position = PITCH.get_center() - Vector2(18 if team == 0 else -18, 0)
	ball.owner_player = striker
	ball.last_touch_team = team
	_carry_t = 0.0
	if team == 0:
		_set_controlled(striker)
	state = "kickoff"
	state_t = 0.0


func _start_match() -> void:
	score = [0, 0]
	clock = MATCH_SECONDS
	_build_teams()
	_place_for_kickoff(0)
	controls.visible = true
	controls.reset()
	_sfx("whistle")
	_show_banner("KICK OFF", 1.2)


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	state_t += delta
	banner_t = maxf(banner_t - delta, 0.0)
	_shake = maxf(_shake - delta * 25.0, 0.0)
	_switch_lock = maxf(_switch_lock - delta, 0.0)

	match state:
		"menu", "fulltime":
			for t in 2:
				for p in teams[t]:
					(p as Footballer).desired = Vector2.ZERO
		"goal":
			for t in 2:
				for p in teams[t]:
					var f := p as Footballer
					f.desired = Vector2.ZERO
			if state_t > 2.8:
				_place_for_kickoff(1 - kickoff_team)
		"kickoff":
			_update_controlled()
			_human(delta)
			for t in 2:
				for p in teams[t]:
					var f := p as Footballer
					if f != controlled and f != ball.owner_player:
						f.move_toward_point(_formation_point(t, teams[t].find(f)), 0.6)
						f.face_toward(ball.position)
			var carrier := ball.owner_player as Footballer
			if carrier != null and carrier != controlled and state_t > 1.0:
				_ai_pass(carrier, teams[carrier.team][4])
			if carrier == null or carrier.position.distance_to(PITCH.get_center()) > 40.0:
				state = "play"
		"play":
			clock -= delta
			if clock <= 0.0:
				_full_time()
				return
			_update_controlled()
			_human(delta)
			_run_ai(delta)

	_separate()
	_ball_logic(delta)
	_follow_camera()
	controls.charge = _charge if _charging else 0.0
	_update_button_labels()
	hud.queue_redraw()


func _follow_camera() -> void:
	var target := ball.position + ball.velocity * 0.25
	if state == "menu":
		target = PITCH.get_center()
	camera.position = target
	camera.offset = Vector2(rng.randf_range(-_shake, _shake), rng.randf_range(-_shake, _shake))


# ------------------------------------------------------------------ human

func _set_controlled(p: Footballer) -> void:
	if controlled == p:
		return
	if controlled:
		controlled.controlled = false
	controlled = p
	if p:
		p.controlled = true


func _update_controlled() -> void:
	if autopilot:
		_set_controlled(null)
		return
	var carrier := ball.owner_player as Footballer
	if carrier and carrier.team == 0:
		_set_controlled(carrier)
		return
	if receiver[0] != null and _switch_lock <= 0.0:
		_set_controlled(receiver[0])
		return
	if _switch_lock > 0.0 or (controlled and controlled.action == "slide"):
		return
	var best: Footballer = null
	var bd := INF
	for p in teams[0]:
		var f := p as Footballer
		if f.is_gk:
			continue
		var d := f.position.distance_to(ball.position)
		if d < bd:
			bd = d
			best = f
	if controlled == null or (best != controlled and bd + 70.0 < controlled.position.distance_to(ball.position)):
		_set_controlled(best)


func _human(delta: float) -> void:
	if controlled == null:
		return
	var mv := controls.get_move()
	var has_ball := ball.owner_player == controlled
	var spd := Footballer.DRIBBLE_SPEED if has_ball else Footballer.RUN_SPEED
	if _charging:
		spd *= 0.55
		_charge = minf(_charge + delta / 0.9, 1.0)
	controlled.desired = mv * spd


func _on_shoot_pressed() -> void:
	if state == "menu" or state == "fulltime":
		return
	if controlled == null:
		return
	if ball.owner_player == controlled:
		_charging = true
		_charge = 0.0
	elif state == "play" and not controlled.busy():
		controlled.start_action("slide")


func _on_shoot_released() -> void:
	if not _charging:
		return
	_charging = false
	if controlled and ball.owner_player == controlled:
		var dir := controls.get_move()
		if dir == Vector2.ZERO:
			dir = controlled.facing
		_shoot(controlled, _assist_aim(controlled, dir), maxf(_charge, 0.2))
	_charge = 0.0


func _on_pass_pressed() -> void:
	if state == "menu" or state == "fulltime" or controlled == null:
		return
	if ball.owner_player == controlled:
		var dir := controls.get_move()
		if dir == Vector2.ZERO:
			dir = controlled.facing
		var t := _best_pass_target(controlled, dir, 0.55)
		if t:
			_pass_to(controlled, t)
		else:
			_kick_ball(controlled, dir, 620.0, 0.0, "pass")
	else:
		# Switch to the teammate nearest the ball (other than the current one).
		var best: Footballer = null
		var bd := INF
		for p in teams[0]:
			var f := p as Footballer
			if f == controlled or f.is_gk:
				continue
			var d := f.position.distance_to(ball.position)
			if d < bd:
				bd = d
				best = f
		if best:
			_set_controlled(best)
			_switch_lock = 1.0


## Nudges shots that are heading roughly at goal into the frame.
func _assist_aim(p: Footballer, dir: Vector2) -> Vector2:
	var gx := PITCH.end.x if p.team == 0 else PITCH.position.x
	if signf(dir.x) != signf(gx - p.position.x) or absf(dir.x) < 0.2:
		return dir
	var t := (gx - p.position.x) / dir.x
	var y := p.position.y + dir.y * t
	var cy := PITCH.get_center().y
	if absf(y - cy) < GOAL_HALF + 110.0:
		y = clampf(y, cy - GOAL_HALF + 18.0, cy + GOAL_HALF - 18.0)
		return (Vector2(gx, y) - p.position).normalized()
	return dir


# ------------------------------------------------------------------ kicking

func _kick_ball(p: Footballer, dir: Vector2, speed: float, lift: float, anim: String) -> void:
	p.facing = dir.normalized()
	p.start_action(anim)
	p.cooldown = 0.3
	ball.position = p.dribble_point()
	ball.kick(dir, speed, lift, p.team)
	receiver[p.team] = null
	_sfx("kick" if anim == "kick" else "pass", 0.0 if anim == "kick" else -4.0)
	if state == "kickoff":
		state = "play"


func _shoot(p: Footballer, dir: Vector2, power: float) -> void:
	var speed := 560.0 + 720.0 * power
	var lift := 60.0 + 190.0 * power
	_kick_ball(p, dir, speed, lift, "kick")
	_shake = 4.0 * power


func _pass_to(p: Footballer, t: Footballer) -> void:
	var d := p.position.distance_to(t.position)
	var lead := t.position + t.velocity * minf(d / 700.0, 0.6)
	var dir := (lead - p.position).normalized()
	var speed := clampf(d * 1.9 + 90.0, 320.0, 1000.0)
	var lift := 0.0
	if d > 650.0:
		lift = 200.0   # long balls go in the air
		speed *= 0.85
	_kick_ball(p, dir, speed, lift, "pass")
	receiver[p.team] = t


func _best_pass_target(p: Footballer, dir: Vector2, min_cos: float) -> Footballer:
	var best: Footballer = null
	var best_score := -INF
	for o in teams[p.team]:
		var t := o as Footballer
		if t == p:
			continue
		var to := t.position - p.position
		var d := to.length()
		if d < 60.0:
			continue
		var c := dir.normalized().dot(to / d)
		if c < min_cos:
			continue
		var s := c * 2.0 - d / 1400.0 - _lane_blocked(p.position, t.position, p.team) * 0.8
		if s > best_score:
			best_score = s
			best = t
	return best


## 0..1: how crowded with opponents the line between two points is.
func _lane_blocked(a: Vector2, b: Vector2, team: int) -> float:
	var worst := 0.0
	for o in teams[1 - team]:
		var e := o as Footballer
		var q := Geometry2D.get_closest_point_to_segment(e.position, a, b)
		var d := q.distance_to(e.position)
		worst = maxf(worst, clampf(1.0 - d / 70.0, 0.0, 1.0))
	return worst


# ------------------------------------------------------------------ ball rules

func _ball_logic(delta: float) -> void:
	if state == "menu" or state == "goal" or state == "fulltime":
		return
	var carrier := ball.owner_player as Footballer
	if carrier:
		_carry_t += delta
		ball.position = carrier.dribble_point().clamp(PITCH.position + Vector2(8, 8), PITCH.end - Vector2(8, 8))
		ball.z = 0.0
		ball.velocity = carrier.velocity
		if carrier.action == "fall":
			ball.kick(carrier.facing.rotated(rng.randf_range(-1, 1)), 120.0, 30.0, carrier.team)
			return
		if state == "kickoff":
			return
		# Tackles on the carrier
		for o in teams[1 - carrier.team]:
			var d := o as Footballer
			if not d.can_touch_ball():
				continue
			var dist := d.position.distance_to(carrier.position)
			if d.action == "slide" and d.dribble_point().distance_to(ball.position) < 26.0:
				# Clean slide: ball goes loose, carrier may go down.
				ball.kick(d.facing, 300.0, 40.0, d.team)
				d.cooldown = 0.25
				if dist < 26.0 and rng.randf() < 0.6:
					carrier.start_action("fall")
				_sfx("kick", -6.0)
				return
			if dist < 24.0 and d.action == "":
				var rate := 1.6 if d.team == 0 else 1.25
				if carrier.is_gk:
					rate = 0.0
				if rng.randf() < rate * delta:
					_take_ball(d)
					carrier.cooldown = 0.6
					return
		return

	if not ball.is_loose():
		return
	# Who touches the loose ball?
	var best: Footballer = null
	var bd := INF
	var bz := ball.z
	for t in 2:
		for o in teams[t]:
			var p := o as Footballer
			if not p.can_touch_ball():
				continue
			var d := p.position.distance_to(ball.position)
			var reach := 18.0
			var max_z := 22.0
			if p.is_gk and _in_own_box(p):
				reach = 30.0 if p.action == "slide" else 22.0
				max_z = 56.0
			elif p.action == "slide":
				reach = 24.0
			if bz > 22.0 and bz < 60.0 and not p.is_gk and d < 20.0 and p.action == "":
				_header(p)
				return
			if d < reach and bz < max_z and d < bd:
				best = p
				bd = d
	if best == null:
		return
	if best.action == "slide" and not best.is_gk:
		ball.kick(best.facing, 320.0, 30.0, best.team)
		best.cooldown = 0.2
		return
	if best.is_gk:
		var spd := ball.velocity.length()
		var catch_chance := 1.0 if spd < 500.0 else (0.7 if spd < 850.0 else 0.4)
		if rng.randf() > catch_chance:
			# Parry
			var away := Vector2(1.0 if best.team == 0 else -1.0, rng.randf_range(-1.2, 1.2)).normalized()
			ball.kick(away, spd * 0.4, 120.0, best.team)
			best.cooldown = 0.3
			_sfx("bounce")
			return
	_take_ball(best)


func _take_ball(p: Footballer) -> void:
	ball.owner_player = p
	ball.last_touch_team = p.team
	ball.velocity = Vector2.ZERO
	ball.z = 0.0
	ball.vz = 0.0
	receiver = [null, null]
	_carry_t = 0.0
	_think[p] = rng.randf_range(0.25, 0.5)


func _header(p: Footballer) -> void:
	var goal := _opp_goal(p.team) + Vector2(0, rng.randf_range(-GOAL_HALF, GOAL_HALF) * 0.8)
	var dir := (goal - p.position).normalized()
	if p.team == 0 and controlled == p and controls.get_move() != Vector2.ZERO:
		dir = controls.get_move().normalized()
	p.facing = dir
	p.start_action("header")
	p.cooldown = 0.3
	ball.kick(dir, maxf(ball.velocity.length() * 0.6, 420.0), 90.0, p.team)
	_sfx("kick", -3.0)


func _in_own_box(p: Footballer) -> bool:
	var gx := PITCH.position.x if p.team == 0 else PITCH.end.x
	return absf(p.position.x - gx) < 330.0 and absf(p.position.y - PITCH.get_center().y) < 300.0


func _own_goal(team: int) -> Vector2:
	return Vector2(PITCH.position.x if team == 0 else PITCH.end.x, PITCH.get_center().y)


func _opp_goal(team: int) -> Vector2:
	return _own_goal(1 - team)


func _on_goal(side: int) -> void:
	if state != "play" and state != "kickoff":
		return
	var scorer := 1 if side == 0 else 0
	score[scorer] += 1
	state = "goal"
	state_t = 0.0
	kickoff_team = scorer   # _place_for_kickoff uses 1 - kickoff_team -> conceding side kicks off
	_charging = false
	_shake = 10.0
	_sfx("cheer")
	_sfx("whistle", -6.0)
	_show_banner("GOAL!", 2.6)
	for p in teams[scorer]:
		(p as Footballer).start_action("celebrate")


func _full_time() -> void:
	state = "fulltime"
	state_t = 0.0
	_charging = false
	controls.visible = false
	controls.reset()
	_sfx("whistle")
	if score[0] > score[1]:
		record["w"] += 1
		for p in teams[0]: (p as Footballer).start_action("celebrate")
	elif score[0] < score[1]:
		record["l"] += 1
		for p in teams[1]: (p as Footballer).start_action("celebrate")
	else:
		record["d"] += 1
	_save_record()


# ------------------------------------------------------------------ AI

func _run_ai(delta: float) -> void:
	var carrier := ball.owner_player as Footballer
	for t in 2:
		var chasers := _chasers(t)
		for o in teams[t]:
			var p := o as Footballer
			if p == controlled:
				continue
			if _think.has(p):
				_think[p] = maxf(float(_think[p]) - delta, 0.0)
			if p.action == "fall" or p.action == "celebrate":
				p.desired = Vector2.ZERO
				continue
			if p.is_gk:
				_ai_keeper(p, delta)
			elif p == carrier:
				_ai_carrier(p)
			elif carrier == null:
				if p == receiver[t] or p == chasers[0]:
					p.move_toward_point(ball.position + ball.velocity * 0.3, 1.0, 10.0)
				else:
					p.move_toward_point(_shape_point(p, false), 0.8)
					p.face_toward(ball.position)
			elif carrier.team == t:
				p.move_toward_point(_shape_point(p, true), 0.9)
			else:
				if p == chasers[0]:
					p.move_toward_point(carrier.dribble_point(), 1.0, 8.0)
					var d := p.position.distance_to(carrier.position)
					var ahead := (carrier.position - p.position).normalized().dot(p.facing) > 0.6
					if t == 1 and d < 70.0 and d > 30.0 and ahead and rng.randf() < 0.9 * delta:
						p.start_action("slide")
				elif p == chasers[1]:
					var g := _own_goal(t)
					p.move_toward_point(carrier.position + (g - carrier.position).normalized() * 130.0, 0.95)
				else:
					p.move_toward_point(_shape_point(p, false), 0.85)
					p.face_toward(ball.position)


## The two outfield players of a team best placed to go for the ball.
## For your team, the player you control counts as the first chaser.
func _chasers(t: int) -> Array:
	var list: Array = []
	for o in teams[t]:
		var p := o as Footballer
		if not p.is_gk:
			list.append(p)
	list.sort_custom(func(a: Footballer, b: Footballer) -> bool:
		return a.position.distance_to(ball.position) < b.position.distance_to(ball.position))
	if t == 0 and controlled and not controlled.is_gk:
		list.erase(controlled)
		list.push_front(controlled)
	return list


## Where a player should stand given the ball: formation shifted with play.
func _shape_point(p: Footballer, attacking: bool) -> Vector2:
	var i: int = teams[p.team].find(p)
	var base := _formation_point(p.team, i)
	var dir := 1.0 if p.team == 0 else -1.0
	var c := PITCH.get_center()
	var shift_x := (ball.position.x - c.x) * 0.6
	if attacking:
		shift_x += dir * PITCH.size.x * 0.12
	var x := base.x + shift_x
	var y := lerpf(base.y, ball.position.y, 0.28)
	# Defenders never drift past the halfway-ish line by too much, forwards stay up.
	if i <= 2:
		x = clampf(x, PITCH.position.x + 140, PITCH.end.x - 140)
	return Vector2(x, y)


func _ai_carrier(p: Footballer) -> void:
	var goal := _opp_goal(p.team)
	var to_goal := goal - p.position
	var dist_goal := to_goal.length()
	var t: float = _think.get(p, 0.0)
	if p == controlled:
		return
	# Threat: nearest opponent
	var near: Footballer = null
	var nd := INF
	for o in teams[1 - p.team]:
		var e := o as Footballer
		var d := e.position.distance_to(p.position)
		if d < nd:
			nd = d
			near = e
	if t <= 0.0:
		_think[p] = 0.25
		if dist_goal < 520.0 and _carry_t > 0.2:
			_ai_shoot(p)
			return
		if nd < 70.0 and _carry_t > 0.35:
			var fwd := to_goal.normalized()
			var mate := _best_pass_target(p, fwd, -0.2)
			if mate and _lane_blocked(p.position, mate.position, p.team) < 0.5:
				_pass_to(p, mate)
				return
		if dist_goal < 700.0 and nd > 80.0 and rng.randf() < 0.2:
			_ai_shoot(p)
			return
	# Dribble toward goal, steering around opponents.
	var dir := to_goal.normalized()
	for o in teams[1 - p.team]:
		var e := o as Footballer
		var off := p.position - e.position
		var d := off.length()
		if d < 140.0 and d > 0.1:
			var side := Vector2(-dir.y, dir.x)
			var s := signf(side.dot(off)) if absf(side.dot(off)) > 2.0 else 1.0
			dir += side * s * (1.0 - d / 140.0) * 1.4
	var target := p.position + dir.normalized() * 100.0
	p.move_toward_point(target, Footballer.DRIBBLE_SPEED / Footballer.RUN_SPEED * 0.97)


func _ai_shoot(p: Footballer) -> void:
	var goal := _opp_goal(p.team)
	var keeper: Footballer = teams[1 - p.team][0]
	var side := 1.0 if keeper.position.y < goal.y else -1.0
	if rng.randf() < 0.25:
		side = -side
	var aim := goal + Vector2(0, side * rng.randf_range(GOAL_HALF * 0.35, GOAL_HALF * 0.85))
	var power := rng.randf_range(0.45, 0.9)
	_shoot(p, (aim - p.position).normalized(), power)


func _ai_pass(p: Footballer, t: Footballer) -> void:
	_pass_to(p, t)


func _ai_keeper(p: Footballer, delta: float) -> void:
	var g := _own_goal(p.team)
	var out := 1.0 if p.team == 0 else -1.0
	if ball.owner_player == p:
		p.desired = Vector2.ZERO
		if _carry_t > 0.8:
			var fwd := Vector2(out, 0)
			var mate := _best_pass_target(p, fwd, 0.0)
			if mate and _lane_blocked(p.position, mate.position, p.team) < 0.4:
				_pass_to(p, mate)
			else:
				_kick_ball(p, Vector2(out, rng.randf_range(-0.5, 0.5)).normalized(), 900.0, 300.0, "kick")
		return
	var cy := g.y
	# React to shots heading at goal.
	if ball.is_loose() and signf(ball.velocity.x) == -out and absf(ball.velocity.x) > 250.0:
		var t := (p.position.x - ball.position.x) / ball.velocity.x
		if t > 0.0 and t < 1.2:
			var py := ball.position.y + ball.velocity.y * t
			py = clampf(py, cy - GOAL_HALF - 20, cy + GOAL_HALF + 20)
			var target := Vector2(p.position.x, py)
			p.move_toward_point(target, 1.0, 8.0)
			if absf(py - p.position.y) > 30.0 and t < 0.28 and p.action == "":
				p.facing = Vector2(0, signf(py - p.position.y))
				p.start_action("slide")
			return
	# Rush out to loose balls in the box.
	if ball.is_loose() and absf(ball.position.x - g.x) < 300.0 and absf(ball.position.y - cy) < 280.0:
		var nearest_opp := INF
		for o in teams[1 - p.team]:
			nearest_opp = minf(nearest_opp, (o as Footballer).position.distance_to(ball.position))
		if p.position.distance_to(ball.position) < nearest_opp + 40.0:
			p.move_toward_point(ball.position, 1.15, 6.0)
			return
	# Otherwise: stay between ball and goal centre.
	var to_ball := ball.position - g
	var depth := lerpf(70.0, 26.0, clampf(to_ball.length() / 900.0, 0.0, 1.0))
	var spot := g + to_ball.normalized() * depth
	spot.x = g.x + out * maxf(absf(spot.x - g.x), 22.0)
	spot.y = clampf(spot.y, cy - GOAL_HALF + 10, cy + GOAL_HALF - 10)
	p.move_toward_point(spot, 1.0, 20.0)
	p.face_toward(ball.position)


# ------------------------------------------------------------------ misc

func _separate() -> void:
	var all: Array = teams[0] + teams[1]
	for i in all.size():
		var a := all[i] as Footballer
		for j in range(i + 1, all.size()):
			var b := all[j] as Footballer
			var d := a.position - b.position
			var l := d.length()
			if l < 18.0 and l > 0.01:
				var push := d / l * (18.0 - l) * 0.5
				a.position += push
				b.position -= push


func _update_button_labels() -> void:
	var has := controlled != null and ball.owner_player == controlled
	controls.shoot_label = "SHOOT" if has else "TACKLE"
	controls.pass_label = "PASS" if has else "SWITCH"


func _show_banner(t: String, secs: float) -> void:
	banner = t
	banner_t = secs


func _unhandled_input(event: InputEvent) -> void:
	var tap := Vector2(-1, -1)
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		tap = (event as InputEventScreenTouch).position
	elif event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		var k := event as InputEventKey
		if state == "menu":
			if k.keycode == KEY_LEFT or k.keycode == KEY_A:
				_cycle_kit(-1)
			elif k.keycode == KEY_RIGHT or k.keycode == KEY_D:
				_cycle_kit(1)
			elif k.keycode == KEY_ENTER or k.keycode == KEY_SPACE:
				_start_match()
		elif state == "fulltime" and state_t > 1.2:
			_to_menu()
		return
	if tap.x < 0:
		return
	_web_fullscreen()
	var vs := hud.size
	if state == "menu":
		if tap.y > vs.y * 0.72:
			_start_match()
		elif tap.x < vs.x * 0.5:
			_cycle_kit(-1)
		else:
			_cycle_kit(1)
	elif state == "fulltime" and state_t > 1.2:
		_to_menu()


func _to_menu() -> void:
	state = "menu"
	state_t = 0.0
	_build_teams()
	_place_for_kickoff(0)
	state = "menu"


func _cycle_kit(d: int) -> void:
	kit_index[0] = posmod(kit_index[0] + d, Kits.TEAMS.size())
	kit_index[1] = Kits.contrasting(kit_index[0], rng)
	_build_teams()
	_place_for_kickoff(0)
	state = "menu"


var _went_fullscreen := false


## First tap in a phone browser goes fullscreen and locks landscape.
func _web_fullscreen() -> void:
	if _went_fullscreen or not OS.has_feature("web") or not DisplayServer.is_touchscreen_available():
		return
	_went_fullscreen = true
	JavaScriptBridge.eval("""
		(function(){
			var el = document.documentElement;
			var req = el.requestFullscreen || el.webkitRequestFullscreen;
			if (!req) return;
			var p = req.call(el);
			if (p && p.then) p.then(function(){
				if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function(){});
			}).catch(function(){});
		})();
	""", true)


# ------------------------------------------------------------------ HUD

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var vs := hud.size
	var home: Dictionary = Kits.TEAMS[kit_index[0]]
	var away: Dictionary = Kits.TEAMS[kit_index[1]]

	if state != "menu":
		# Scoreboard
		var w := 360.0
		var r := Rect2(vs.x * 0.5 - w * 0.5, 10, w, 46)
		hud.draw_rect(r, Color(0, 0, 0, 0.6))
		hud.draw_rect(Rect2(r.position + Vector2(8, 10), Vector2(14, 26)), home["shirt"])
		hud.draw_rect(Rect2(r.end - Vector2(22, 36), Vector2(14, 26)), away["shirt"])
		_text(font, Vector2(r.position.x + 30, r.position.y + 32), home["short"], 22, Color.WHITE, 0)
		_text(font, Vector2(r.end.x - 30, r.position.y + 32), away["short"], 22, Color.WHITE, 2)
		_text(font, Vector2(vs.x * 0.5, r.position.y + 34), "%d - %d" % [score[0], score[1]], 30, Color.WHITE, 1)
		var secs := int(ceil(maxf(clock, 0.0)))
		_text(font, Vector2(vs.x * 0.5, r.end.y + 24), "%d:%02d" % [secs / 60, secs % 60], 20, Color(1, 1, 0.8), 1)

	if banner_t > 0.0:
		var a := clampf(banner_t * 2.0, 0.0, 1.0)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.4), banner, 84, Color(1, 0.95, 0.6, a), 1)

	if state == "menu":
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.2), "2D FOOTBALL", 72, Color(1, 1, 1), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.3), "5-a-side  -  3 minute match", 22, Color(1, 1, 1, 0.75), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.43), "YOUR TEAM", 20, Color(1, 1, 1, 0.6), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.52), "<   %s   >" % home["name"], 40, home["shirt"].lightened(0.25), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.62), "vs  %s" % away["name"], 26, away["shirt"].lightened(0.25), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.69), "tap left / right to change team", 16, Color(1, 1, 1, 0.5), 1)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 260.0)
		hud.draw_rect(Rect2(vs.x * 0.5 - 170, vs.y * 0.76, 340, 64), Color(0.15, 0.55, 0.2, 0.9))
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.76 + 44), "KICK OFF", 34, Color(1, 1, 1, pulse), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y - 18), "Record  W %d  D %d  L %d     v%s" % [record["w"], record["d"], record["l"], version], 16, Color(1, 1, 1, 0.5), 1)
	elif state == "fulltime":
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, minf(state_t, 0.55)))
		var res := "YOU WIN!" if score[0] > score[1] else ("DRAW" if score[0] == score[1] else "YOU LOSE")
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.36), "FULL TIME", 40, Color(1, 1, 1, 0.8), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.5), res, 72, Color(1, 0.9, 0.5), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.6), "%s %d - %d %s" % [home["name"], score[0], score[1], away["name"]], 26, Color.WHITE, 1)
		if state_t > 1.2:
			_text(font, Vector2(vs.x * 0.5, vs.y * 0.74), "Tap to continue", 24, Color(1, 1, 1, 0.6 + 0.4 * sin(state_t * 4.0)), 1)
	else:
		_text(font, Vector2(vs.x - 14, vs.y - 8), "v" + version, 14, Color(1, 1, 1, 0.35), 2)


func _text(font: Font, p: Vector2, s: String, size: int, col: Color, align: int) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := p.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	hud.draw_string_outline(font, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, col.a * 0.7))
	hud.draw_string(font, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ------------------------------------------------------------------ save

func _load_record() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		var v: Variant = f.get_var()
		if v is Dictionary:
			record = v


func _save_record() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var(record)
