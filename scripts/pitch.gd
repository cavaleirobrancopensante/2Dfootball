extends Node2D
## Draws the pitch: striped grass, markings, goals with nets, and the
## surrounding boards and stands.

var pitch := Rect2(0, 0, 2200, 1300)
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
	for i in 2600:
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
	var stripes := 14
	var sw := pitch.size.x / stripes
	for i in stripes:
		var c := Color("#4c9a3e") if i % 2 == 0 else Color("#438c37")
		draw_rect(Rect2(pitch.position.x + i * sw, pitch.position.y, sw + 1, pitch.size.y), c)
	# Markings
	var line := Color(1, 1, 1, 0.85)
	var w := 4.0
	draw_rect(pitch, line, false, w)
	var c := pitch.get_center()
	draw_line(Vector2(c.x, pitch.position.y), Vector2(c.x, pitch.end.y), line, w)
	draw_arc(c, 150, 0, TAU, 64, line, w)
	draw_circle(c, 6, line)
	for side in [0, 1]:
		var gx: float = pitch.position.x if side == 0 else pitch.end.x
		var s := 1.0 if side == 0 else -1.0
		# Penalty box, six-yard box, spot, arc
		draw_rect(_box(gx, s, 330, 300), line, false, w)
		draw_rect(_box(gx, s, 120, 170), line, false, w)
		draw_circle(Vector2(gx + s * 220, c.y), 5, line)
		var arc_c := Vector2(gx + s * 220, c.y)
		var start := -0.75 if side == 0 else PI - 0.75
		draw_arc(arc_c, 150, start, start + 1.5, 24, line, w)
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
