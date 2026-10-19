extends Node2D
## Draws the pitch: striped grass, markings, goals with nets, and the
## surrounding boards and stands.

var pitch := Rect2(0, 0, 3600, 2330)
var goal_half_width := 130.0
var goal_depth := 46.0


func _draw() -> void:
	var outer := pitch.grow(260)
	# Stands / surroundings
	draw_rect(outer, Color("#2b3a2b"))
	draw_rect(pitch.grow(70), Color("#3f7a35"))
	# Crowd dots in the stands
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crowd := [Color("#c84040"), Color("#4060c0"), Color("#e0d050"), Color("#e0e0e0"), Color("#40a060"), Color("#202020")]
	for i in 5200:
		var p := Vector2(rng.randf_range(outer.position.x, outer.end.x), rng.randf_range(outer.position.y, outer.end.y))
		if pitch.grow(120).has_point(p):
			continue
		draw_rect(Rect2(p, Vector2(4, 4)), crowd[rng.randi() % crowd.size()].darkened(rng.randf() * 0.4))
	# Advertising boards
	var board := pitch.grow(96)
	var cols := [Color("#1d4fa0"), Color("#c02a2a"), Color("#e8e8e8"), Color("#1f8040")]
	var x := board.position.x
	var k := 0
	while x < board.end.x:
		draw_rect(Rect2(x, board.position.y, 160, 16), cols[k % 4])
		draw_rect(Rect2(x, board.end.y - 16, 160, 16), cols[(k + 2) % 4])
		x += 160
		k += 1
	# Grass stripes
	var stripes := 18
	var sw := pitch.size.x / stripes
	for i in stripes:
		var c := Color("#4c9a3e") if i % 2 == 0 else Color("#438c37")
		draw_rect(Rect2(pitch.position.x + i * sw, pitch.position.y, sw + 1, pitch.size.y), c)
	# Markings
	var line := Color(1, 1, 1, 0.85)
	var w := 4.0
	var m := pitch.size.x / 105.0   # pixels per metre; markings use real sizes
	draw_rect(pitch, line, false, w)
	var c := pitch.get_center()
	draw_line(Vector2(c.x, pitch.position.y), Vector2(c.x, pitch.end.y), line, w)
	draw_arc(c, 9.15 * m, 0, TAU, 72, line, w)
	draw_circle(c, 6, line)
	for side in [0, 1]:
		var gx: float = pitch.position.x if side == 0 else pitch.end.x
		var s := 1.0 if side == 0 else -1.0
		# Penalty box, six-yard box, spot, arc
		draw_rect(_box(gx, s, 16.5 * m, 20.16 * m), line, false, w)
		draw_rect(_box(gx, s, 5.5 * m, 9.16 * m), line, false, w)
		var spot := Vector2(gx + s * 11.0 * m, c.y)
		draw_circle(spot, 5, line)
		var half_angle := acos((16.5 - 11.0) / 9.15)
		var start := -half_angle if side == 0 else PI - half_angle
		draw_arc(spot, 9.15 * m, start, start + half_angle * 2.0, 32, line, w)
		# Corner arcs
		for cy_ in [pitch.position.y, pitch.end.y]:
			var a0 := 0.0 if side == 0 else PI / 2.0
			if cy_ == pitch.end.y:
				a0 = -PI / 2.0 if side == 0 else PI
			draw_arc(Vector2(gx, cy_), 1.0 * m, a0, a0 + PI / 2.0, 8, line, w)
		_draw_goal(gx, s)


func _box(gx: float, s: float, depth: float, half_h: float) -> Rect2:
	var cy := pitch.get_center().y
	var x0 := gx if s > 0 else gx - depth
	return Rect2(x0, cy - half_h, depth, half_h * 2)


func _draw_goal(gx: float, s: float) -> void:
	var cy := pitch.get_center().y
	var back := gx - s * goal_depth
	var x0 := minf(gx, back)
	var r := Rect2(x0, cy - goal_half_width, goal_depth, goal_half_width * 2)
	draw_rect(r, Color(0.85, 0.85, 0.85, 0.25))
	# Net mesh
	var net := Color(1, 1, 1, 0.45)
	var yy := r.position.y
	while yy <= r.end.y:
		draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), net, 1.0)
		yy += 10.0
	var xx := r.position.x
	while xx <= r.end.x:
		draw_line(Vector2(xx, r.position.y), Vector2(xx, r.end.y), net, 1.0)
		xx += 10.0
	# Posts and frame
	var post := Color(1, 1, 1)
	draw_line(Vector2(gx, cy - goal_half_width), Vector2(back, cy - goal_half_width), post, 5.0)
	draw_line(Vector2(gx, cy + goal_half_width), Vector2(back, cy + goal_half_width), post, 5.0)
	draw_line(Vector2(back, cy - goal_half_width), Vector2(back, cy + goal_half_width), Color(1, 1, 1, 0.7), 3.0)
	draw_circle(Vector2(gx, cy - goal_half_width), 5, post)
	draw_circle(Vector2(gx, cy + goal_half_width), 5, post)
