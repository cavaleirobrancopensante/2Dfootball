extends SceneTree
## Usage: godot --headless --fixed-fps 60 --script res://tools/simulate.gd
## AI vs AI: plays N matches at high speed and prints scorelines.
var m: Node
var t := 0.0
var results: Array = []
func _initialize() -> void:
	m = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
func _process(delta: float) -> bool:
	t += delta
	if int(t) % 60 == 0 and int(t - delta) % 60 != 0:
		print("t=", int(t), " state=", m.state, " clock=", int(m.clock), " ", m.score)
	if m.state == "menu" and t > 0.2:
		m.autopilot = true
		m._start_match()
	if m.state == "fulltime":
		results.append(m.score.duplicate())
		print("match ", results.size(), ": ", m.score)
		m._to_menu()
	return results.size() >= 4
