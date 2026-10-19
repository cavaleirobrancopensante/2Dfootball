extends Node2D
## Runs an 11-a-side match: you (team 0, attacking right) against the computer.
## Quick match: shows its own team picker. Career: call configure() first;
## `finished` is emitted with the result when the player leaves the match.
## States: menu -> kickoff -> play -> goal -> kickoff ... -> fulltime.

signal finished(result: Dictionary)

const PITCH := Rect2(0, 0, 3600, 2330)     # 105 x 68 m
const METRE := 3600.0 / 105.0
const GOAL_HALF := 130.0
const BOX_DEPTH := 16.5 * METRE
const BOX_HALF := 20.16 * METRE
const MATCH_SECONDS := 300.0               # five real minutes = 90 on the clock
const SAVE_PATH := "user://record.save"
const GRAVITY := 980.0

var version: String = ProjectSettings.get_setting("application/config/version", "dev")
var rng := RandomNumberGenerator.new()

var config: Dictionary = {}          # career mode: {teams: [team, team]}
var career_mode := false
var team_data: Array = [{}, {}]
var world: Node2D
var ball: Ball
var camera: Camera2D
var controls: Controls
var hud: Control
var teams: Array = [[], []]          # Array of Array[Footballer]
var kit_index := [0, 1]
var score := [0, 0]
var scorers: Array = []              # [team, pid, name]
var record := {"w": 0, "d": 0, "l": 0}

var state := "menu"
var state_t := 0.0
var clock := MATCH_SECONDS
var kickoff_team := 0
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var paused := false

var controlled: Footballer
var autopilot := false               # testing: the computer plays both sides
var receiver: Array = [null, null]   # intended pass receiver per team
var last_kicker: Footballer
var _switch_lock := 0.0
var _charge_btn := ""
var _think: Dictionary = {}
var _carry_t := 0.0
var _sounds: Dictionary = {}
var _shake := 0.0
var _went_fullscreen := false
var kickoff_partner: Array = [null, null]


func configure(cfg: Dictionary) -> void:
	config = cfg
	career_mode = true


func _ready() -> void:
	rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_record()
	var pitch_node := Node2D.new()
	pitch_node.set_script(preload("res://scripts/pitch.gd"))
	pitch_node.set("pitch", PITCH)
	pitch_node.set("goal_half_width", GOAL_HALF)
	pitch_node.z_index = -10
	add_child(pitch_node)

	world = Node2D.new()
	world.y_sort_enabled = true
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	ball = Ball.new()
	ball.pitch = PITCH
	ball.goal_half_width = GOAL_HALF
	ball.goal.connect(_on_goal)
	ball.bounced.connect(func(s: float) -> void: _sfx("bounce", linear_to_db(clampf(s / 900.0, 0.05, 1.0))))
	world.add_child(ball)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.85, 0.85)
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
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	controls = Controls.new()
	controls.button_down.connect(_on_button_down)
	controls.button_up.connect(_on_button_up)
	controls.pause_pressed.connect(_toggle_pause)
	layer.add_child(controls)
	controls.visible = false

	for n in ["kick", "whistle", "cheer", "bounce", "pass"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.wav" % n)
		p.max_polyphony = 3
		add_child(p)
		_sounds[n] = p

	if career_mode:
		team_data = config["teams"]
		_build_teams()
		_start_match()
	else:
		kit_index[1] = Kits.contrasting(kit_index[0], rng)
		_make_exhibition_teams()
		_build_teams()
		_place_for_kickoff(0)
		state = "menu"
	camera.position = PITCH.get_center()


func _sfx(n: String, db := 0.0) -> void:
	var p: AudioStreamPlayer = _sounds[n]
	p.volume_db = db
	p.pitch_scale = rng.randf_range(0.94, 1.06)
	p.play()


# ------------------------------------------------------------------ teams

func _make_exhibition_teams() -> void:
	for t in 2:
		var kit: Dictionary = Kits.TEAMS[kit_index[t]].duplicate()
		var roles: Array = ["GK"] + Ratings.roles("4-4-2")
		var list: Array = []
		for i in roles.size():
			list.append({"id": -1, "name": "No. %d" % (i + 1), "role": roles[i], "stats": _random_stats(roles[i], 68.0),
				"energy": 1.0, "look": Kits.random_look(rng)})
		team_data[t] = {"name": kit["name"], "short": kit["short"], "kit": kit, "formation": "4-4-2", "players": list}


func _random_stats(role: String, base: float) -> Dictionary:
	var s := {}
	for a in Ratings.ATTRS:
		var v := base + rng.randfn(0, 7)
		if role == "GK":
			v += 8.0 if a in ["reflexes", "handling"] else -15.0
		elif a in ["reflexes", "handling"]:
			v -= 40.0
		elif role == "FWD" and a in ["shooting", "pace", "dribbling"]:
			v += 6.0
		elif role == "DEF" and a in ["tackling", "heading", "strength"]:
			v += 6.0
		s[a] = clampi(int(v), 1, 99)
	return s


func _build_teams() -> void:
	for t in teams:
		for p in t:
			(p as Node).queue_free()
	teams = [[], []]
	for team in 2:
		var td: Dictionary = team_data[team]
		var kit: Dictionary = td["kit"]
		var list: Array = td["players"]
		for i in list.size():
			var pd: Dictionary = list[i]
			var f := Footballer.new()
			f.team = team
			f.number = i + 1
			f.pid = int(pd.get("id", -1))
			f.player_name = str(pd.get("name", ""))
			f.role = pd["role"]
			f.stats = pd["stats"]
			f.energy = clampf(float(pd.get("energy", 1.0)), 0.2, 1.0)
			f.pitch = PITCH
			f.setup(pd["look"], kit, pd["role"] == "GK")
			world.add_child(f)
			teams[team].append(f)


## Spot for a player in their team's shape (formation fractions, mirrored for team 1).
func _formation_point(team: int, i: int) -> Vector2:
	var spots: Array = Ratings.spots(team_data[team].get("formation", Ratings.DEFAULT_FORMATION))
	var fr: Vector2 = spots[mini(i, spots.size() - 1)]
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
			p.sprinting = false
			p.stop_action()
			p.cooldown = 0.0
			p.facing = Vector2.RIGHT if t == 0 else Vector2.LEFT
	# The most advanced, most central forward takes it; the nearest teammate gets the pass.
	var striker: Footballer = null
	var best := -INF
	for i in teams[team].size():
		var sp := _formation_point(team, i)
		var sc := -absf(sp.x - PITCH.get_center().x) - absf(sp.y - PITCH.get_center().y) * 0.5
		if i > 0 and sc > best:
			best = sc
			striker = teams[team][i]
	var partner: Footballer = null
	var pd := INF
	for o in teams[team]:
		var f := o as Footballer
		if f != striker and not f.is_gk and f.position.distance_to(PITCH.get_center()) < pd:
			pd = f.position.distance_to(PITCH.get_center())
			partner = f
	kickoff_partner[team] = partner
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
	scorers = []
	clock = MATCH_SECONDS
	if not career_mode:
		_make_exhibition_teams()
		_build_teams()
	_place_for_kickoff(0)
	controls.visible = true
	controls.reset()
	_sfx("whistle")
	_show_banner("KICK OFF", "", 1.2)


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if paused:
		return
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
					(p as Footballer).desired = Vector2.ZERO
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
				_pass_to(carrier, kickoff_partner[carrier.team])
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
	_update_buttons()
	hud.queue_redraw()


func _follow_camera() -> void:
	var target := ball.position + ball.velocity * 0.25
	if state == "menu":
		target = PITCH.get_center()
	camera.position = target
	camera.offset = Vector2(rng.randf_range(-_shake, _shake), rng.randf_range(-_shake, _shake))


func _our_possession(team: int) -> bool:
	var carrier := ball.owner_player as Footballer
	if carrier:
		return carrier.team == team
	return receiver[team] != null


# ------------------------------------------------------------------ human

func _set_controlled(p: Footballer) -> void:
	if controlled == p:
		return
	if controlled:
		controlled.controlled = false
		controlled.charge = 0.0
		controlled.sprinting = false
	controlled = p
	_charge_btn = ""
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
	if controlled == null or (best != controlled and bd + 110.0 < controlled.position.distance_to(ball.position)):
		_set_controlled(best)


func _human(_delta: float) -> void:
	if controlled == null:
		return
	var mv := controls.get_move()
	var has_ball := ball.owner_player == controlled
	controlled.sprinting = controls.is_held("tackle") and _our_possession(0) and controlled.energy > 0.12
	var spd := controlled.dribble_speed() if has_ball else controlled.max_speed()
	var c := 0.0
	if _charge_btn != "" and has_ball:
		c = _charge_amount(_charge_btn)
		spd *= 0.6
	elif _charge_btn != "":
		_charge_btn = ""
	controlled.charge = c
	controls.charge = c
	controls.charge_button = _charge_btn
	controlled.desired = mv * spd


func _charge_amount(b: String) -> float:
	var t := controls.held_time(b)
	if b == "pass":
		return clampf((t - 0.2) / 0.8, 0.0, 1.0)   # short taps show no bar
	return clampf(t / 0.9, 0.0, 1.0)


func _aim_dir() -> Vector2:
	var d := controls.get_move()
	return d.normalized() if d != Vector2.ZERO else controlled.facing


func _on_button_down(b: String) -> void:
	if paused or controlled == null or not (state == "play" or state == "kickoff"):
		return
	var has_ball := ball.owner_player == controlled
	match b:
		"pass", "shoot", "cross":
			if has_ball:
				_charge_btn = b
			elif b == "pass":
				_switch_player()
		"tackle":
			if not _our_possession(0) and state == "play" and not controlled.busy():
				controlled.start_action("slide")


func _on_button_up(b: String, held: float) -> void:
	if paused or controlled == null:
		return
	var has_ball := ball.owner_player == controlled
	if b == "tackle":
		if has_ball and held < 0.22 and not controlled.busy() and controlled.cooldown <= 0.0:
			controlled.start_action("skill")
			controlled.cooldown = 0.0
		return
	if b != _charge_btn:
		return
	var c := _charge_amount(b)
	_charge_btn = ""
	controlled.charge = 0.0
	controls.charge = 0.0
	if not has_ball:
		return
	match b:
		"pass":
			if held < 0.22:
				_short_pass(controlled, _aim_dir())
			else:
				_long_ball(controlled, _aim_dir(), c)
		"shoot":
			_shoot(controlled, _assist_aim(controlled, _aim_dir()), maxf(c, 0.15))
		"cross":
			_cross(controlled, _aim_dir(), maxf(c, 0.1))


func _switch_player() -> void:
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


func _toggle_pause() -> void:
	if state == "menu" or state == "fulltime":
		return
	paused = not paused
	get_tree().paused = paused
	controls.reset()


# ------------------------------------------------------------------ kicking (all use the player's ratings)

func _kick_ball(p: Footballer, dir: Vector2, speed: float, lift: float, anim: String) -> void:
	if p.is_gk and p.action == "hold":
		anim = "gk_throw" if anim == "pass" and lift < 100.0 else "gk_punt"
	p.facing = dir.normalized()
	p.start_action(anim)
	p.cooldown = 0.3
	ball.position = p.dribble_point().clamp(PITCH.position + Vector2(8, 8), PITCH.end - Vector2(8, 8))
	ball.kick(dir, speed, lift, p.team)
	last_kicker = p
	receiver[p.team] = null
	_sfx("kick" if anim == "kick" else "pass", 0.0 if anim == "kick" else -4.0)
	if state == "kickoff":
		state = "play"


func _wobble(dir: Vector2, sigma: float) -> Vector2:
	return dir.rotated(rng.randfn(0.0, sigma))


func _shoot(p: Footballer, dir: Vector2, power: float) -> void:
	var pw := p.st("power")
	var speed := lerpf(430.0, 640.0, pw) + power * lerpf(420.0, 780.0, pw)
	var sigma := lerpf(0.13, 0.02, p.st("shooting")) * (1.0 + 0.8 * power * power) / p.fatigue()
	var lift := 50.0 + 170.0 * power
	if power > 0.85:
		lift += rng.randf_range(0.0, 160.0)   # leaning back: it can sail over
	_kick_ball(p, _wobble(dir, sigma), speed, lift, "kick")
	_shake = 4.0 * power


func _pass_to(p: Footballer, t: Footballer) -> void:
	var d := p.position.distance_to(t.position)
	if d > 800.0:
		_lofted(p, t.position + t.velocity * 0.5, lerpf(0.16, 0.03, p.st("passing")))
		receiver[p.team] = t
		return
	var lead := t.position + t.velocity * minf(d / 700.0, 0.6)
	var dir := (lead - p.position).normalized()
	var acc := p.st("passing")
	var speed := clampf(d * 1.9 + 90.0, 320.0, 1250.0) * rng.randf_range(1.0 - (1.0 - acc) * 0.2, 1.0 + (1.0 - acc) * 0.2)
	_kick_ball(p, _wobble(dir, lerpf(0.12, 0.015, acc) / p.fatigue()), speed, 0.0, "pass")
	receiver[p.team] = t


func _short_pass(p: Footballer, dir: Vector2) -> void:
	var t := _best_pass_target(p, dir, 0.55, 0.0)
	if t:
		_pass_to(p, t)
	else:
		_kick_ball(p, _wobble(dir, lerpf(0.12, 0.015, p.st("passing"))), 600.0, 0.0, "pass")


## Long ball: the bar sets the distance; it goes to a teammate near that distance if there is one.
func _long_ball(p: Footballer, dir: Vector2, c: float) -> void:
	var want := lerpf(400.0, 1800.0, c)
	var best: Footballer = null
	var bd := INF
	for o in teams[p.team]:
		var t := o as Footballer
		if t == p:
			continue
		var to := t.position - p.position
		if to.length() < 150.0 or dir.dot(to.normalized()) < 0.7:
			continue
		var miss := absf(to.length() - want)
		if miss < bd and miss < 350.0:
			bd = miss
			best = t
	var sigma := lerpf(0.16, 0.03, p.st("passing")) / p.fatigue()
	if best:
		_lofted(p, best.position + best.velocity * 0.6, sigma)
		receiver[p.team] = best
	else:
		_lofted(p, p.position + dir * want, sigma)


## Cross: from the attacking third it drops into the box; elsewhere it's a lofted ball.
## The bar is the power: too little falls short, too much sails long.
func _cross(p: Footballer, dir: Vector2, c: float) -> void:
	var goal := _opp_goal(p.team)
	var s := 1.0 if p.team == 0 else -1.0
	var target: Vector2
	if absf(goal.x - p.position.x) < 1300.0:
		var mate: Footballer = null
		var md := INF
		var spot := goal - Vector2(s * 300.0, 0)
		for o in teams[p.team]:
			var t := o as Footballer
			if t == p or t.is_gk:
				continue
			var d := t.position.distance_to(spot)
			if d < md:
				md = d
				mate = t
		target = Vector2(goal.x - s * rng.randf_range(150.0, 420.0), goal.y + rng.randf_range(-200.0, 200.0))
		if mate and md < 600.0:
			target.y = lerpf(target.y, mate.position.y, 0.5)
			receiver[p.team] = mate
	else:
		target = p.position + dir * lerpf(400.0, 1400.0, c)
	var power_fit := lerpf(0.65, 1.3, c)
	target = p.position + (target - p.position) * power_fit
	_lofted(p, target, lerpf(0.14, 0.03, p.st("crossing")) / p.fatigue(), 280.0)


func _lofted(p: Footballer, target: Vector2, sigma: float, vz := 0.0) -> void:
	var d := p.position.distance_to(target)
	if vz <= 0.0:
		vz = clampf(d * 0.3, 170.0, 420.0)
	var flight := 2.0 * vz / GRAVITY
	var speed := clampf(d / flight * 1.06, 250.0, 1700.0)
	var r: Variant = receiver[p.team]
	_kick_ball(p, _wobble((target - p.position).normalized(), sigma), speed, vz, "kick")
	receiver[p.team] = r


func _best_pass_target(p: Footballer, dir: Vector2, min_cos: float, vision := 1.0) -> Footballer:
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
		var s := c * 2.0 - d / 1400.0 - _lane_blocked(p.position, t.position, p.team) * 0.8 * vision
		if s > best_score:
			best_score = s
			best = t
	return best


func _lane_blocked(a: Vector2, b: Vector2, team: int) -> float:
	var worst := 0.0
	for o in teams[1 - team]:
		var e := o as Footballer
		var q := Geometry2D.get_closest_point_to_segment(e.position, a, b)
		worst = maxf(worst, clampf(1.0 - q.distance_to(e.position) / 70.0, 0.0, 1.0))
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
		for o in teams[1 - carrier.team]:
			var d := o as Footballer
			if not d.can_touch_ball():
				continue
			var dist := d.position.distance_to(carrier.position)
			if carrier.is_gk and carrier.action == "hold":
				continue   # nobody tackles a keeper with the ball in his hands
			if d.action == "slide" and d.dribble_point().distance_to(ball.position) < 26.0:
				var win := lerpf(0.45, 0.95, d.st("tackling")) * (1.0 - 0.3 * carrier.st("dribbling"))
				if carrier.evade_t > 0.0:
					win *= 0.3
				d.cooldown = 0.25
				if rng.randf() < win:
					ball.kick(d.facing, 300.0, 40.0, d.team)
					last_kicker = d
					if dist < 26.0 and rng.randf() < 0.5:
						carrier.start_action("fall")
					_sfx("kick", -6.0)
					return
				continue
			if dist < 24.0 and d.action == "" and carrier.evade_t <= 0.0 and not carrier.is_gk:
				var edge := d.st("tackling") - 0.7 * carrier.st("dribbling") - 0.3 * carrier.st("strength") + 0.2 * d.st("strength")
				var rate := clampf(0.6 + edge, 0.15, 1.3) * 1.5
				if rng.randf() < rate * delta:
					_take_ball(d)
					carrier.cooldown = 0.6
					return
		return

	if not ball.is_loose():
		return
	var bz := ball.z
	# Aerial ball: headers, contested by heading and strength.
	if bz > 22.0 and bz < 70.0:
		var contenders: Array = []
		for t in 2:
			for o in teams[t]:
				var p := o as Footballer
				if p.can_touch_ball() and not p.is_gk and p.action == "" and p.position.distance_to(ball.position) < 22.0:
					contenders.append(p)
		if not contenders.is_empty():
			var total := 0.0
			for p in contenders:
				total += 0.2 + (p as Footballer).st("heading") * 0.7 + (p as Footballer).st("strength") * 0.3
			var r := rng.randf() * total
			for p in contenders:
				var f := p as Footballer
				r -= 0.2 + f.st("heading") * 0.7 + f.st("strength") * 0.3
				if r <= 0.0:
					_header(f)
					return
	var best: Footballer = null
	var bd := INF
	for t in 2:
		for o in teams[t]:
			var p := o as Footballer
			if not p.can_touch_ball():
				continue
			var d := p.position.distance_to(ball.position)
			var reach := 18.0
			var max_z := 22.0
			if p.is_gk and _in_own_box(p):
				reach = lerpf(26.0, 34.0, p.st("reflexes")) if p.action == "slide" else lerpf(20.0, 26.0, p.st("reflexes"))
				max_z = 58.0
			elif p.action == "slide":
				reach = 24.0
			if d < reach and bz < max_z and d < bd:
				best = p
				bd = d
	if best == null:
		return
	if best.action == "slide" and not best.is_gk:
		ball.kick(best.facing, 320.0, 30.0, best.team)
		last_kicker = best
		best.cooldown = 0.2
		return
	var spd := ball.velocity.length()
	if best.is_gk:
		var chance := 1.0 if spd < 500.0 else (0.75 if spd < 850.0 else 0.45)
		chance = minf(chance * lerpf(0.75, 1.2, best.st("handling")), 1.0)
		if rng.randf() > chance:
			var away := Vector2(1.0 if best.team == 0 else -1.0, rng.randf_range(-1.2, 1.2)).normalized()
			ball.kick(away, spd * 0.4, 120.0, best.team)
			best.cooldown = 0.3
			_sfx("bounce")
			return
	elif spd > 650.0:
		# Heavy first touch on a fast ball
		var fumble := clampf((spd - 650.0) / 900.0, 0.0, 0.45) * (1.1 - best.st("dribbling"))
		if rng.randf() < fumble:
			ball.velocity = ball.velocity.rotated(rng.randf_range(-1.2, 1.2)) * 0.3
			best.cooldown = 0.25
			return
	_take_ball(best)


func _take_ball(p: Footballer) -> void:
	ball.owner_player = p
	ball.last_touch_team = p.team
	ball.velocity = Vector2.ZERO
	ball.z = 0.0
	ball.vz = 0.0
	last_kicker = p
	receiver = [null, null]
	_carry_t = 0.0
	_think[p] = rng.randf_range(0.25, 0.5)


func _header(p: Footballer) -> void:
	var own := _own_goal(p.team)
	var near_opp := ball.position.distance_to(_opp_goal(p.team)) < 700.0
	var dir: Vector2
	if near_opp:
		var aim := _opp_goal(p.team) + Vector2(0, rng.randf_range(-GOAL_HALF, GOAL_HALF) * 0.75)
		dir = (aim - p.position).normalized()
	else:
		dir = (ball.position - own).normalized()   # clear it away from your own goal
	if p == controlled and controls.get_move() != Vector2.ZERO:
		dir = controls.get_move().normalized()
	dir = _wobble(dir, lerpf(0.3, 0.05, p.st("heading")))
	p.facing = dir
	p.start_action("header")
	p.cooldown = 0.3
	ball.kick(dir, lerpf(360.0, 650.0, p.st("heading")), 40.0 if near_opp else 160.0, p.team)
	last_kicker = p
	_sfx("kick", -3.0)


func _in_own_box(p: Footballer) -> bool:
	var gx := PITCH.position.x if p.team == 0 else PITCH.end.x
	return absf(p.position.x - gx) < BOX_DEPTH and absf(p.position.y - PITCH.get_center().y) < BOX_HALF


func _own_goal(team: int) -> Vector2:
	return Vector2(PITCH.position.x if team == 0 else PITCH.end.x, PITCH.get_center().y)


func _opp_goal(team: int) -> Vector2:
	return _own_goal(1 - team)


## Where an airborne ball will come down (or where a rolling ball is heading).
func _landing_point() -> Vector2:
	if ball.z > 2.0:
		var t := (ball.vz + sqrt(ball.vz * ball.vz + 2.0 * GRAVITY * ball.z)) / GRAVITY
		return ball.position + ball.velocity * t * 0.9
	return ball.position + ball.velocity * 0.3


func _on_goal(side: int) -> void:
	if state != "play" and state != "kickoff":
		return
	var scorer_team := 1 if side == 0 else 0
	score[scorer_team] += 1
	var who := ""
	if last_kicker and last_kicker.team == scorer_team:
		who = last_kicker.player_name
		scorers.append([scorer_team, last_kicker.pid, "%s %d'" % [who, game_minute()]])
	else:
		who = "Own goal"
		scorers.append([scorer_team, -1, "Own goal %d'" % game_minute()])
	state = "goal"
	state_t = 0.0
	kickoff_team = scorer_team
	_charge_btn = ""
	_shake = 10.0
	_sfx("cheer")
	_sfx("whistle", -6.0)
	_show_banner("GOAL!", who, 2.6)
	for p in teams[scorer_team]:
		(p as Footballer).start_action("celebrate")


func _full_time() -> void:
	state = "fulltime"
	state_t = 0.0
	_charge_btn = ""
	controls.visible = false
	controls.reset()
	_sfx("whistle")
	if score[0] > score[1]:
		for p in teams[0]: (p as Footballer).start_action("celebrate")
	elif score[0] < score[1]:
		for p in teams[1]: (p as Footballer).start_action("celebrate")
	if not career_mode:
		if score[0] > score[1]:
			record["w"] += 1
		elif score[0] < score[1]:
			record["l"] += 1
		else:
			record["d"] += 1
		_save_record()


func _result() -> Dictionary:
	var energy := {}
	for t in 2:
		for o in teams[t]:
			var p := o as Footballer
			if p.pid >= 0:
				energy[p.pid] = p.energy
	return {"score": score.duplicate(), "scorers": scorers.duplicate(), "energy": energy}


## Career: finish a paused match quickly by simulating the remaining time.
func _sim_rest() -> void:
	var left := clampf(clock / MATCH_SECONDS, 0.0, 1.0)
	for t in 2:
		var goals := 0
		var l := 1.4 * left
		var L := exp(-l)
		var p := rng.randf()
		while p > L:
			goals += 1
			p *= rng.randf()
		for i in goals:
			score[t] += 1
			var f: Footballer = teams[t][rng.randi_range(teams[t].size() - 5, teams[t].size() - 1)]
			scorers.append([t, f.pid, f.player_name])
	paused = false
	get_tree().paused = false
	clock = 0.0
	_full_time()


# ------------------------------------------------------------------ AI

func _run_ai(delta: float) -> void:
	var carrier := ball.owner_player as Footballer
	for t in 2:
		var chasers := _chasers(t)
		for o in teams[t]:
			var p := o as Footballer
			if p == controlled:
				continue
			p.sprinting = false
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
					p.sprinting = p.energy > 0.3
					p.move_toward_point(_landing_point(), 1.0, 10.0)
				elif ball.z > 20.0 and ball.last_touch_team == t and p == chasers[1]:
					# Attack the cross / long ball too
					p.move_toward_point(_landing_point() + Vector2(0, 40), 1.0, 10.0)
				else:
					p.move_toward_point(_shape_point(p, ball.last_touch_team == t), 0.8)
					p.face_toward(ball.position)
			elif carrier.team == t:
				p.move_toward_point(_shape_point(p, true), 0.9)
			else:
				if p == chasers[0]:
					p.sprinting = p.energy > 0.35
					p.move_toward_point(carrier.dribble_point(), 1.0, 8.0)
					var d := p.position.distance_to(carrier.position)
					var ahead := (carrier.position - p.position).normalized().dot(p.facing) > 0.6
					var slide_rate := 0.4 + 1.0 * p.st("tackling")
					if d < 70.0 and d > 30.0 and ahead and rng.randf() < slide_rate * 0.6 * delta:
						p.start_action("slide")
				elif p == chasers[1]:
					var g := _own_goal(t)
					p.move_toward_point(carrier.position + (g - carrier.position).normalized() * 130.0, 0.95)
				else:
					p.move_toward_point(_shape_point(p, false), 0.85)
					p.face_toward(ball.position)


func _chasers(t: int) -> Array:
	var list: Array = []
	for o in teams[t]:
		var p := o as Footballer
		if not p.is_gk:
			list.append(p)
	var target := _landing_point()
	list.sort_custom(func(a: Footballer, b: Footballer) -> bool:
		return a.position.distance_to(target) / a.max_speed() < b.position.distance_to(target) / b.max_speed())
	if t == 0 and controlled and not controlled.is_gk:
		list.erase(controlled)
		list.push_front(controlled)
	return list


func _shape_point(p: Footballer, attacking: bool) -> Vector2:
	var i: int = teams[p.team].find(p)
	var base := _formation_point(p.team, i)
	var dir := 1.0 if p.team == 0 else -1.0
	var c := PITCH.get_center()
	var shift_x := (ball.position.x - c.x) * 0.5
	if attacking:
		shift_x += dir * PITCH.size.x * (0.14 if p.role == "FWD" else (0.11 if p.role == "MID" else 0.06))
	var x := base.x + shift_x
	# Squeeze toward the ball's side, more for central players.
	var y := lerpf(base.y, ball.position.y, 0.22)
	x = clampf(x, PITCH.position.x + 140, PITCH.end.x - 140)
	return Vector2(x, y)


func _ai_carrier(p: Footballer) -> void:
	if p == controlled:
		return
	var goal := _opp_goal(p.team)
	var to_goal := goal - p.position
	var dist_goal := to_goal.length()
	var t: float = _think.get(p, 0.0)
	var nd := INF
	for o in teams[1 - p.team]:
		nd = minf(nd, (o as Footballer).position.distance_to(p.position))
	if t <= 0.0:
		_think[p] = 0.25
		var range_ := lerpf(450.0, 720.0, p.st("shooting"))
		if dist_goal < range_ and _carry_t > 0.2:
			_ai_shoot(p)
			return
		# Near the byline with a teammate in the box: cross it.
		var cy := PITCH.get_center().y
		if absf(goal.x - p.position.x) < 650.0 and absf(p.position.y - cy) > 420.0 and rng.randf() < 0.5:
			for o in teams[p.team]:
				var m := o as Footballer
				if m != p and not m.is_gk and m.position.distance_to(goal) < 650.0:
					_cross(p, to_goal.normalized(), rng.randf_range(0.45, 0.75))
					return
		if nd < 70.0 and _carry_t > 0.35:
			var mate := _best_pass_target(p, to_goal.normalized(), -0.2, p.st("passing"))
			if mate and _lane_blocked(p.position, mate.position, p.team) < 0.5:
				_pass_to(p, mate)
				return
			if p.st("dribbling") > 0.6 and rng.randf() < p.st("dribbling") * 0.5 and p.cooldown <= 0.0:
				p.start_action("skill")
		if dist_goal < 850.0 and nd > 80.0 and rng.randf() < 0.15:
			_ai_shoot(p)
			return
	var dir := to_goal.normalized()
	for o in teams[1 - p.team]:
		var e := o as Footballer
		var off := p.position - e.position
		var d := off.length()
		if d < 140.0 and d > 0.1:
			var side := Vector2(-dir.y, dir.x)
			var s := signf(side.dot(off)) if absf(side.dot(off)) > 2.0 else 1.0
			dir += side * s * (1.0 - d / 140.0) * 1.4
	p.sprinting = nd > 120.0 and p.energy > 0.4
	p.move_toward_point(p.position + dir.normalized() * 100.0, p.dribble_speed() / p.max_speed() * 0.97)


func _ai_shoot(p: Footballer) -> void:
	var goal := _opp_goal(p.team)
	var keeper: Footballer = teams[1 - p.team][0]
	var side := 1.0 if keeper.position.y < goal.y else -1.0
	if rng.randf() < 0.25:
		side = -side
	var aim := goal + Vector2(0, side * rng.randf_range(GOAL_HALF * 0.35, GOAL_HALF * 0.85))
	_shoot(p, (aim - p.position).normalized(), rng.randf_range(0.45, 0.9))


func _ai_keeper(p: Footballer, _delta: float) -> void:
	var g := _own_goal(p.team)
	var out := 1.0 if p.team == 0 else -1.0
	if ball.owner_player == p:
		p.desired = Vector2.ZERO
		if p.action == "" and _in_own_box(p):
			p.start_action("hold")
		if _carry_t > 1.0:
			var mate := _best_pass_target(p, Vector2(out, 0), 0.0)
			if mate and _lane_blocked(p.position, mate.position, p.team) < 0.4:
				_pass_to(p, mate)
			else:
				_long_ball(p, Vector2(out, rng.randf_range(-0.5, 0.5)).normalized(), rng.randf_range(0.6, 0.95))
		return
	var cy := g.y
	if ball.is_loose() and signf(ball.velocity.x) == -out and absf(ball.velocity.x) > 250.0:
		var t := (p.position.x - ball.position.x) / ball.velocity.x
		if t > 0.0 and t < 1.2:
			var py := clampf(ball.position.y + ball.velocity.y * t, cy - GOAL_HALF - 20, cy + GOAL_HALF + 20)
			p.move_toward_point(Vector2(p.position.x, py), lerpf(0.85, 1.15, p.st("reflexes")), 8.0)
			if absf(py - p.position.y) > 30.0 and t < 0.28 and p.action == "":
				p.facing = Vector2(0, signf(py - p.position.y))
				p.start_action("slide")
			return
	if ball.is_loose() and absf(ball.position.x - g.x) < BOX_DEPTH * 0.8 and absf(ball.position.y - cy) < BOX_HALF * 0.7:
		var nearest_opp := INF
		for o in teams[1 - p.team]:
			nearest_opp = minf(nearest_opp, (o as Footballer).position.distance_to(ball.position))
		if p.position.distance_to(ball.position) < nearest_opp + 40.0:
			p.move_toward_point(ball.position, 1.15, 6.0)
			return
	var to_ball := ball.position - g
	var depth := lerpf(80.0, 26.0, clampf(to_ball.length() / 1400.0, 0.0, 1.0))
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


func _update_buttons() -> void:
	var has := controlled != null and ball.owner_player == controlled
	var ours := _our_possession(0)
	controls.labels["pass"] = "PASS" if has else "SWITCH"
	controls.labels["tackle"] = "DRIBBLE" if ours else "TACKLE"


func _show_banner(t: String, sub: String, secs: float) -> void:
	banner = t
	banner_sub = sub
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
			elif k.keycode == KEY_ESCAPE:
				finished.emit({"aborted": true})
		elif state == "fulltime" and state_t > 1.2:
			_leave_fulltime()
		return
	if tap.x < 0:
		return
	_web_fullscreen()
	var vs := hud.size
	if paused:
		for b in _pause_buttons(vs):
			if (b["rect"] as Rect2).has_point(tap):
				match b["id"]:
					"resume":
						_toggle_pause()
					"quit":
						paused = false
						get_tree().paused = false
						finished.emit({"aborted": true})
					"sim":
						_sim_rest()
		return
	if state == "menu":
		if Rect2(0, 0, 200, 80).has_point(tap):
			finished.emit({"aborted": true})
		elif tap.y > vs.y * 0.72:
			_start_match()
		elif tap.x < vs.x * 0.5:
			_cycle_kit(-1)
		else:
			_cycle_kit(1)
	elif state == "fulltime" and state_t > 1.2:
		_leave_fulltime()


func _leave_fulltime() -> void:
	if career_mode:
		finished.emit(_result())
	else:
		_to_menu()


func _pause_buttons(vs: Vector2) -> Array:
	var list: Array = [{"id": "resume", "label": "RESUME"}]
	list.append({"id": "sim", "label": "SIMULATE REST"} if career_mode else {"id": "quit", "label": "QUIT MATCH"})
	for i in list.size():
		list[i]["rect"] = Rect2(vs.x * 0.5 - 170, vs.y * 0.42 + i * 90, 340, 70)
	return list


func _to_menu() -> void:
	state = "menu"
	state_t = 0.0
	_make_exhibition_teams()
	_build_teams()
	_place_for_kickoff(0)
	state = "menu"


func _cycle_kit(d: int) -> void:
	kit_index[0] = posmod(kit_index[0] + d, Kits.TEAMS.size())
	kit_index[1] = Kits.contrasting(kit_index[0], rng)
	_to_menu()


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
	var home: Dictionary = team_data[0]
	var away: Dictionary = team_data[1]

	if state != "menu":
		var w := 380.0
		var r := Rect2(vs.x * 0.5 - w * 0.5, 10, w, 46)
		hud.draw_rect(r, Color(0, 0, 0, 0.6))
		hud.draw_rect(Rect2(r.position + Vector2(8, 10), Vector2(14, 26)), home["kit"]["shirt"])
		hud.draw_rect(Rect2(r.end - Vector2(22, 36), Vector2(14, 26)), away["kit"]["shirt"])
		_text(font, Vector2(r.position.x + 30, r.position.y + 32), home["short"], 22, Color.WHITE, 0)
		_text(font, Vector2(r.end.x - 30, r.position.y + 32), away["short"], 22, Color.WHITE, 2)
		_text(font, Vector2(vs.x * 0.5, r.position.y + 34), "%d - %d" % [score[0], score[1]], 30, Color.WHITE, 1)
		_text(font, Vector2(vs.x * 0.5, r.end.y + 24), "%d'" % game_minute(), 20, Color(1, 1, 0.8), 1)
		if state != "fulltime":
			_draw_minimap(vs)
		# Controlled player: name and stamina
		if controlled and controls.visible:
			var nm := controlled.player_name if controlled.player_name != "" else "Player %d" % controlled.number
			_text(font, Vector2(84, 32), nm, 18, Color.WHITE, 0)
			hud.draw_rect(Rect2(84, 40, 120, 8), Color(0, 0, 0, 0.5))
			var e := controlled.energy
			hud.draw_rect(Rect2(85, 41, 118 * e, 6), Color(0.9, 0.3, 0.2).lerp(Color(0.3, 0.9, 0.4), e))

	if banner_t > 0.0:
		var a := clampf(banner_t * 2.0, 0.0, 1.0)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.4), banner, 84, Color(1, 0.95, 0.6, a), 1)
		if banner_sub != "":
			_text(font, Vector2(vs.x * 0.5, vs.y * 0.4 + 50), banner_sub, 30, Color(1, 1, 1, a), 1)

	if paused:
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.32), "PAUSED", 56, Color.WHITE, 1)
		for b in _pause_buttons(vs):
			var rr: Rect2 = b["rect"]
			hud.draw_rect(rr, Color(0.15, 0.45, 0.2, 0.95))
			_text(font, rr.position + Vector2(rr.size.x * 0.5, 46), b["label"], 28, Color.WHITE, 1)
		return

	if state == "menu":
		var hk: Dictionary = home["kit"]
		var ak: Dictionary = away["kit"]
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
		_text(font, Vector2(24, 48), "< Menu", 26, Color(1, 1, 1, 0.8), 0)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.2), "QUICK MATCH", 64, Color(1, 1, 1), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.3), "11-a-side  -  5 minutes", 22, Color(1, 1, 1, 0.75), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.43), "YOUR TEAM", 20, Color(1, 1, 1, 0.6), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.52), "<   %s   >" % home["name"], 40, (hk["shirt"] as Color).lightened(0.25), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.62), "vs  %s" % away["name"], 26, (ak["shirt"] as Color).lightened(0.25), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.69), "tap left / right to change team", 16, Color(1, 1, 1, 0.5), 1)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 260.0)
		hud.draw_rect(Rect2(vs.x * 0.5 - 170, vs.y * 0.76, 340, 64), Color(0.15, 0.55, 0.2, 0.9))
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.76 + 44), "KICK OFF", 34, Color(1, 1, 1, pulse), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y - 18), "Record  W %d  D %d  L %d     v%s" % [record["w"], record["d"], record["l"], version], 16, Color(1, 1, 1, 0.5), 1)
	elif state == "fulltime":
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, minf(state_t, 0.6)))
		var res := "YOU WIN!" if score[0] > score[1] else ("DRAW" if score[0] == score[1] else "YOU LOSE")
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.24), "FULL TIME", 40, Color(1, 1, 1, 0.8), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.37), res, 66, Color(1, 0.9, 0.5), 1)
		_text(font, Vector2(vs.x * 0.5, vs.y * 0.47), "%s %d - %d %s" % [home["name"], score[0], score[1], away["name"]], 26, Color.WHITE, 1)
		var y := vs.y * 0.55
		for sc in scorers:
			var side: int = sc[0]
			_text(font, Vector2(vs.x * (0.3 if side == 0 else 0.7), y), str(sc[2]), 18, Color(1, 1, 1, 0.8), 1)
			y += 22
		if state_t > 1.2:
			_text(font, Vector2(vs.x * 0.5, vs.y * 0.9), "Tap to continue", 24, Color(1, 1, 1, 0.6 + 0.4 * sin(state_t * 4.0)), 1)
	else:
		_text(font, Vector2(vs.x - 14, vs.y - 8), "v" + version, 14, Color(1, 1, 1, 0.35), 2)


func game_minute() -> int:
	return clampi(int((1.0 - clock / MATCH_SECONDS) * 90.0), 0, 90)


## Small radar of the whole pitch, bottom centre.
func _draw_minimap(vs: Vector2) -> void:
	var w := 190.0
	var h := w * PITCH.size.y / PITCH.size.x
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y - h - 10, w, h)
	hud.draw_rect(r.grow(3), Color(0, 0, 0, 0.45))
	hud.draw_rect(r, Color(0.25, 0.5, 0.25, 0.5))
	hud.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
	hud.draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color(1, 1, 1, 0.3), 1.0)
	var k := w / PITCH.size.x
	for t in 2:
		var col: Color = team_data[t]["kit"]["shirt"]
		for o in teams[t]:
			var f := o as Footballer
			var p := r.position + (f.position - PITCH.position) * k
			hud.draw_circle(p, 3.6 if f == controlled else 2.6, Color.WHITE if f == controlled else col)
			if f != controlled:
				hud.draw_arc(p, 2.8, 0, TAU, 8, Color(0, 0, 0, 0.6), 1.0)
	hud.draw_circle(r.position + (ball.position - PITCH.position) * k, 2.2, Color(1, 1, 0.3))


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
