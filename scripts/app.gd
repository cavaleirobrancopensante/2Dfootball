extends Node
## The app: main menu, manager career screens, and handing off to matches.

const MATCH_SCENE := preload("res://scenes/match.tscn")

var version: String = ProjectSettings.get_setting("application/config/version", "dev")
var career: Career
var layer: CanvasLayer
var root: Control
var content: VBoxContainer          # current tab content (hub)
var dialog: Control
var match_node: Node
var tab := "match"
var table_div := -1
var market_filter := "ALL"
var market_free := false
var lineup_slot := -1               # squad screen: slot waiting for a player
var _pending_season_end := false


func _ready() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.make_theme()
	layer.add_child(root)
	show_main_menu()


func _frame() -> MarginContainer:
	UI.clear(root)
	dialog = null
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	root.add_child(m)
	return m


# ------------------------------------------------------------------ main menu

func show_main_menu() -> void:
	var m := _frame()
	var v := UI.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)
	v.add_child(UI.label("2D FOOTBALL", 72, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Manage a club. Play the matches. 11 v 11.", 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.spacer(16))
	var col := UI.vbox(12)
	col.custom_minimum_size = Vector2(440, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(col)
	if Career.has_save():
		var saved := Career.load_saved()
		if saved:
			var c: Dictionary = saved.clubs[saved.user]
			col.add_child(UI.accent_button("CONTINUE  ·  %s, %d" % [c["name"], saved.year], func() -> void:
				career = saved
				show_hub("match")))
	if Career.old_save():
		var note := UI.label("Your 5-a-side career from v1.1 can't continue in 11-a-side. Start a new one.", 16, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(note)
	col.add_child(UI.button("NEW CAREER", func() -> void: _confirm_new_career(), 24, Vector2(0, 60)))
	col.add_child(UI.button("QUICK MATCH", func() -> void: _play_quick_match(), 24, Vector2(0, 60)))
	v.add_child(UI.spacer(20))
	v.add_child(UI.label("v" + version + "   ·   all clubs and players are fictional (edit data/database.json)", 15, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_CENTER))


func _confirm_new_career() -> void:
	if Career.has_save() and not Career.old_save():
		_dialog("Start a new career?", "Your saved career will be replaced.", [
			["START NEW", func() -> void: show_new_career()], ["CANCEL", func() -> void: _close_dialog()]])
	else:
		show_new_career()


func _play_quick_match() -> void:
	layer.visible = false
	match_node = MATCH_SCENE.instantiate()
	match_node.finished.connect(func(_r: Dictionary) -> void:
		match_node.queue_free()
		match_node = null
		layer.visible = true
		show_main_menu())
	add_child(match_node)


# ------------------------------------------------------------------ new career

var _pick_div := 3


func show_new_career() -> void:
	if career == null or career.user != -1:
		career = Career.new()
		career.new_from_database()
	var m := _frame()
	var v := UI.vbox(10)
	m.add_child(v)
	var top := UI.hbox(10)
	top.add_child(UI.button("<", func() -> void: show_main_menu(), 24, Vector2(60, 50)))
	top.add_child(UI.label("Choose your club", 34))
	v.add_child(top)
	var tabs := UI.hbox(8)
	for d in career.divisions.size():
		var dd := d
		var b := UI.button(career.division_names[d], func() -> void:
			_pick_div = dd
			show_new_career(), 18, Vector2(0, 46))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if d == _pick_div:
			b.add_theme_stylebox_override("normal", UI._box(UI.ACCENT, 8))
		tabs.add_child(b)
	v.add_child(tabs)
	var hint := "Top flight: big budgets, high expectations." if _pick_div == 0 else ("Start at the bottom and climb." if _pick_div == 3 else "")
	v.add_child(UI.label(hint, 17, UI.MUTED))
	var list := UI.vbox(6)
	list.add_child(UI.row([["", 30], ["Club", 0], ["Rating", 90, HORIZONTAL_ALIGNMENT_CENTER], ["Budget", 120, HORIZONTAL_ALIGNMENT_RIGHT], ["Stadium", 120, HORIZONTAL_ALIGNMENT_RIGHT]], Callable(), Color(0, 0, 0, 0), 16))
	var ids: Array = career.divisions[_pick_div].duplicate()
	ids.sort_custom(func(a: int, b: int) -> bool: return career.team_rating(a) > career.team_rating(b))
	for cid in ids:
		var c: Dictionary = career.clubs[cid]
		var r := career.team_rating(cid)
		var row := UI.row([["", 30], [c["name"], 0], [str(r), 90, HORIZONTAL_ALIGNMENT_CENTER, UI.rating_colour(r)],
			[Ratings.money(c["budget"]), 120, HORIZONTAL_ALIGNMENT_RIGHT], ["%d" % c["stadium"], 120, HORIZONTAL_ALIGNMENT_RIGHT]],
			func() -> void: _confirm_club(cid))
		_add_swatch(row, c["home"])
		list.add_child(row)
	v.add_child(UI.scroll(list))


func _add_swatch(row: Control, kit: Dictionary) -> void:
	var h: HBoxContainer = row.get_child(0) if row.get_child(0) is HBoxContainer else row.get_child(0)
	if h == null:
		return
	var first: Control = h.get_child(0)
	var sw := UI.swatch(kit, 24)
	h.add_child(sw)
	h.move_child(sw, 0)
	first.queue_free()


func _confirm_club(cid: int) -> void:
	var c: Dictionary = career.clubs[cid]
	var best := ""
	var top := -1
	for p in career.squad(cid):
		var o := Ratings.overall(p)
		if o > top:
			top = o
			best = "%s (%s, %d)" % [p["name"], p["pos"], o]
	_dialog(c["name"], "%s\nSquad rating %d   ·   Budget %s\nBest player: %s" % [career.division_names[c["division"]], career.team_rating(cid), Ratings.money(c["budget"]), best], [
		["TAKE THE JOB", func() -> void:
			career.start(cid)
			career.save()
			show_hub("match")],
		["BACK", func() -> void: _close_dialog()]])


# ------------------------------------------------------------------ hub

func show_hub(t := "") -> void:
	if t != "":
		tab = t
	var m := _frame()
	var outer := UI.vbox(10)
	m.add_child(outer)
	var c: Dictionary = career.clubs[career.user]
	# Header
	var head := UI.hbox(12)
	head.add_child(UI.swatch(c["home"], 30))
	head.add_child(UI.label(c["name"], 28))
	head.add_child(UI.label(career.division_names[c["division"]], 18, UI.MUTED))
	var sp := UI.spacer(0, true)
	head.add_child(sp)
	var ev := career.current_event()
	head.add_child(UI.label("Season %d  ·  Week %d/%d" % [career.year, career.week + 1, career.calendar.size()], 18, UI.MUTED))
	head.add_child(UI.label(Ratings.money(c["budget"]), 24, UI.GOLD))
	outer.add_child(head)
	var body := UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var nav := UI.vbox(6)
	nav.custom_minimum_size = Vector2(170, 0)
	for item in [["match", "MATCH"], ["squad", "SQUAD"], ["table", "TABLE"], ["fixtures", "FIXTURES"], ["cup", "CUP"], ["transfers", "TRANSFERS"], ["club", "CLUB"]]:
		var id: String = item[0]
		var b := UI.button(item[1], func() -> void:
			lineup_slot = -1
			show_hub(id), 19, Vector2(0, 50))
		if id == tab:
			b.add_theme_stylebox_override("normal", UI._box(UI.ACCENT, 8))
		nav.add_child(b)
	nav.add_child(UI.spacer(0, true))
	nav.add_child(UI.button("SAVE & EXIT", func() -> void:
		career.save()
		show_main_menu(), 16, Vector2(0, 44)))
	body.add_child(nav)
	content = UI.vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	content.custom_minimum_size.x = 0
	body.add_child(content)
	match tab:
		"match": _tab_match()
		"squad": _tab_squad()
		"table": _tab_table()
		"fixtures": _tab_fixtures()
		"cup": _tab_cup()
		"transfers": _tab_transfers()
		"club": _tab_club()


func _tab_match() -> void:
	var ev := career.current_event()
	content.add_child(UI.label(career.event_name(ev), 24, UI.GOLD))
	var m := career.user_match()
	if m.is_empty():
		content.add_child(UI.label("No match for you this week — you're out of the cup.", 22))
		content.add_child(UI.label("The other clubs play on. Your players get a week to recover.", 18, UI.MUTED))
		content.add_child(UI.spacer(10))
		var b := UI.accent_button("CONTINUE", func() -> void: _advance({}))
		b.custom_minimum_size = Vector2(260, 60)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		content.add_child(b)
		return
	var home: int = m["h"]
	var away: int = m["a"]
	var opp := away if home == career.user else home
	var hc: Dictionary = career.clubs[home]
	var ac: Dictionary = career.clubs[away]
	var vs := UI.hbox(16)
	vs.alignment = BoxContainer.ALIGNMENT_CENTER
	vs.add_child(UI.swatch(hc["home"], 34))
	vs.add_child(UI.label(hc["name"], 30))
	vs.add_child(UI.label("vs", 24, UI.MUTED))
	vs.add_child(UI.label(ac["name"], 30))
	var away_kit: Dictionary = ac["away"] if Career.kits_clash(hc["home"], ac["home"]) else ac["home"]
	vs.add_child(UI.swatch(away_kit, 34))
	content.add_child(UI.panel(vs))
	var info := UI.hbox(30)
	info.add_child(UI.label("%s: %s" % ["Home" if home == career.user else "Away", hc["name"] + "'s ground"], 18, UI.MUTED))
	info.add_child(UI.label("Your team %d   ·   %s %d" % [career.team_rating(career.user), career.clubs[opp]["short"], career.team_rating(opp)], 18, UI.MUTED))
	content.add_child(info)
	# Lineup summary
	var lv := UI.vbox(4)
	var roles := career.roles_for(career.user)
	career.validate_lineup(career.user)
	content.add_child(UI.row([["", 70], ["Your lineup  (%s)" % career.clubs[career.user]["formation"], 0], ["OVR", 70, HORIZONTAL_ALIGNMENT_CENTER], ["Fitness", 170]], Callable(), Color(0, 0, 0, 0), 16))
	var lineup: Array = career.clubs[career.user]["lineup"]
	for i in lineup.size():
		var p: Dictionary = career.players[lineup[i]]
		var o := Ratings.overall(p, roles[i])
		var r := UI.row([[roles[i], 70, HORIZONTAL_ALIGNMENT_LEFT, UI.GOLD], [p["name"], 0], [str(o), 70, HORIZONTAL_ALIGNMENT_CENTER, UI.rating_colour(o)], ["", 170]], Callable(), Color(1, 1, 1, 0.04))
		_put_bar(r, float(p["condition"]) / 100.0)
		lv.add_child(r)
	content.add_child(UI.scroll(lv))
	var btns := UI.hbox(14)
	btns.add_child(UI.accent_button("PLAY MATCH", func() -> void: _play_career_match(), 26, Vector2(280, 66)))
	btns.add_child(UI.button("SIMULATE", func() -> void: _advance({}), 22, Vector2(200, 66)))
	btns.add_child(UI.button("EDIT LINEUP", func() -> void: show_hub("squad"), 20, Vector2(200, 66)))
	content.add_child(btns)


func _put_bar(row: Control, v: float) -> void:
	var h: HBoxContainer = row.get_child(0)
	var last: Control = h.get_child(h.get_child_count() - 1)
	var col := Color(0.85, 0.3, 0.25).lerp(Color(0.3, 0.85, 0.4), clampf((v - 0.4) / 0.6, 0.0, 1.0))
	var b := UI.bar(v, 120, col)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var holder := UI.hbox(6)
	holder.custom_minimum_size.x = last.custom_minimum_size.x
	holder.add_child(b)
	holder.add_child(UI.label("%d%%" % int(v * 100), 15, UI.MUTED))
	h.add_child(holder)
	last.queue_free()


# ------------------------------------------------------------------ squad

func _tab_squad() -> void:
	var cid := career.user
	var c: Dictionary = career.clubs[cid]
	career.validate_lineup(cid)
	var top := UI.hbox(8)
	top.add_child(UI.label("Formation", 18, UI.MUTED))
	for f in Ratings.FORMATIONS:
		var ff: String = f
		var b := UI.button(f, func() -> void:
			c["formation"] = ff
			career.validate_lineup(cid)
			show_hub("squad"), 17, Vector2(76, 44))
		if f == c["formation"]:
			b.add_theme_stylebox_override("normal", UI._box(UI.ACCENT, 8))
		top.add_child(b)
	top.add_child(UI.spacer(0, true))
	top.add_child(UI.button("AUTO PICK", func() -> void:
		career.auto_lineup(cid)
		show_hub("squad"), 18, Vector2(140, 44)))
	content.add_child(top)
	# Lineup slots
	var roles := career.roles_for(cid)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in roles.size():
		var ii := i
		var pid: int = c["lineup"][i] if i < c["lineup"].size() else -1
		var nm: String = career.players[pid]["name"] if pid >= 0 else "—"
		var short_nm: String = nm.split(" ", false)[-1] if nm != "—" else nm
		var b := UI.button("%s  %s" % [roles[i], short_nm], func() -> void:
			lineup_slot = -1 if lineup_slot == ii else ii
			show_hub("squad"), 14, Vector2(0, 40))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		if lineup_slot == i:
			b.add_theme_stylebox_override("normal", UI._box(Color("#b08a20"), 8))
		grid.add_child(b)
	content.add_child(grid)
	content.add_child(UI.label("Tap a slot, then a player to put him there." if lineup_slot == -1 else "Now tap the player for the %s slot." % roles[lineup_slot], 15, UI.MUTED))
	var list := UI.vbox(4)
	list.add_child(UI.row([["", 44], ["Name", 0], ["Pos", 50], ["Age", 46, HORIZONTAL_ALIGNMENT_CENTER], ["OVR", 50, HORIZONTAL_ALIGNMENT_CENTER], ["Fitness", 170], ["Value", 90, HORIZONTAL_ALIGNMENT_RIGHT]], Callable(), Color(0, 0, 0, 0), 15))
	var sq := career.squad(cid)
	var order := {"GK": 0, "DEF": 1, "MID": 2, "FWD": 3}
	sq.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if order[a["pos"]] != order[b["pos"]]:
			return order[a["pos"]] < order[b["pos"]]
		return Ratings.overall(a) > Ratings.overall(b))
	for p in sq:
		var pid: int = p["id"]
		var idx: int = c["lineup"].find(pid)
		var mark: String = roles[idx] if idx >= 0 else ""
		var o := Ratings.overall(p)
		var name: String = p["name"] + ("  (inj %dw)" % p["injury"] if p["injury"] > 0 else "")
		var r := UI.row([[mark, 44, HORIZONTAL_ALIGNMENT_LEFT, UI.GOLD], [name, 0, HORIZONTAL_ALIGNMENT_LEFT, Color("#ff8a80") if p["injury"] > 0 else Color.WHITE],
			[p["pos"], 50], [str(p["age"]), 46, HORIZONTAL_ALIGNMENT_CENTER], [str(o), 50, HORIZONTAL_ALIGNMENT_CENTER, UI.rating_colour(o)],
			["", 170], [Ratings.money(Ratings.value(p)), 90, HORIZONTAL_ALIGNMENT_RIGHT, UI.MUTED]],
			func() -> void: _squad_tap(pid), Color(1, 1, 1, 0.07) if idx >= 0 else Color(0, 0, 0, 0))
		var h: HBoxContainer = r.get_child(0)
		var fit_holder: Control = h.get_child(5)
		var holder := UI.hbox(6)
		holder.custom_minimum_size.x = 170
		var v := float(p["condition"]) / 100.0
		var bcol := Color(0.85, 0.3, 0.25).lerp(Color(0.3, 0.85, 0.4), clampf((v - 0.4) / 0.6, 0.0, 1.0))
		var b := UI.bar(v, 110, bcol)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(b)
		holder.add_child(UI.label("%d%%" % int(v * 100), 14, UI.MUTED))
		h.add_child(holder)
		h.move_child(holder, 5)
		fit_holder.queue_free()
		list.add_child(r)
	content.add_child(UI.scroll(list))


func _squad_tap(pid: int) -> void:
	if lineup_slot >= 0:
		var c: Dictionary = career.clubs[career.user]
		var p: Dictionary = career.players[pid]
		var roles := career.roles_for(career.user)
		if (roles[lineup_slot] == "GK") != (p["pos"] == "GK"):
			_toast("Keepers go in the GK slot, outfield players in the others.")
			return
		if p["injury"] > 0:
			_toast("%s is injured." % p["name"])
			return
		var lineup: Array = c["lineup"]
		var cur := lineup.find(pid)
		if cur >= 0:
			lineup[cur] = lineup[lineup_slot]
		lineup[lineup_slot] = pid
		lineup_slot = -1
		show_hub("squad")
	else:
		_player_card(pid)


# ------------------------------------------------------------------ player card

func _player_card(pid: int) -> void:
	var p: Dictionary = career.players[pid]
	var mine: bool = p["club"] == career.user
	var v := UI.vbox(6)
	var head := UI.hbox(12)
	head.add_child(UI.label(p["name"], 30))
	var o := Ratings.overall(p)
	head.add_child(UI.label(str(o), 30, UI.rating_colour(o)))
	v.add_child(head)
	var club_name: String = career.clubs[p["club"]]["name"] if p["club"] >= 0 else "Free agent"
	v.add_child(UI.label("%s  ·  age %d  ·  %s  ·  %s" % [p["pos"], p["age"], p.get("nation", ""), club_name], 18, UI.MUTED))
	v.add_child(UI.label("Value %s   ·   Wage %s/wk   ·   Fitness %d%%%s" % [Ratings.money(Ratings.value(p)), Ratings.money(Ratings.wage(p)),
		int(p["condition"]), ("   ·   injured %dw" % p["injury"]) if p["injury"] > 0 else ""], 17))
	v.add_child(UI.label("Season: %d games, %d goals   ·   Career: %d games, %d goals   ·   Potential: %s" % [p["s_apps"], p["s_goals"], p["apps"], p["goals"], _potential_text(p)], 16, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 4)
	for a in Ratings.ATTRS:
		if (a == "reflexes" or a == "handling") and p["pos"] != "GK":
			continue
		var val: int = p["stats"][a]
		var h := UI.hbox(8)
		var l := UI.label(Ratings.LABELS[a], 16)
		l.custom_minimum_size.x = 140
		h.add_child(l)
		var b := UI.bar(val / 100.0, 120, UI.rating_colour(val))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		h.add_child(UI.label(str(val), 16, UI.rating_colour(val)))
		grid.add_child(h)
	v.add_child(grid)
	var actions: Array = []
	if mine:
		actions.append(["SELL", func() -> void: _sell(pid)])
		actions.append(["RELEASE", func() -> void:
			_dialog("Release %s?" % p["name"], "He leaves for free and joins the free agents.", [
				["RELEASE", func() -> void:
					var why := career.release(pid)
					_after_transfer(why)],
				["CANCEL", func() -> void: _close_dialog()]])])
	else:
		var price := career.asking_price(pid)
		var why := career.can_buy(pid)
		actions.append(["%s %s" % ["SIGN" if p["club"] == -1 else "BUY", Ratings.money(price)], func() -> void:
			if why != "":
				_toast(why)
				return
			_dialog("Sign %s?" % p["name"], "Fee %s   ·   Wage %s/wk\nBudget after: %s" % [Ratings.money(price), Ratings.money(Ratings.wage(p)), Ratings.money(career.clubs[career.user]["budget"] - price)], [
				["CONFIRM", func() -> void: _after_transfer(career.buy(pid))],
				["CANCEL", func() -> void: _close_dialog()]])])
	actions.append(["CLOSE", func() -> void: _close_dialog()])
	_dialog_node(v, actions)


func _potential_text(p: Dictionary) -> String:
	var pot: int = p["potential"]
	if p["age"] >= 29:
		return "fully developed"
	var lo := maxi(pot - 4, Ratings.overall(p))
	return "%d–%d" % [lo, pot + 4]


func _sell(pid: int) -> void:
	var p: Dictionary = career.players[pid]
	var offer := career.sale_offer(pid)
	if offer.is_empty():
		_dialog("No offers", "Nobody wants to pay for %s right now." % p["name"], [["OK", func() -> void: _close_dialog()]])
		return
	_dialog("Offer for %s" % p["name"], "%s offer %s.\nHis value: %s" % [career.clubs[offer["club"]]["name"], Ratings.money(offer["price"]), Ratings.money(Ratings.value(p))], [
		["ACCEPT", func() -> void: _after_transfer(career.sell(pid, offer))],
		["DECLINE", func() -> void: _close_dialog()]])


func _after_transfer(why: String) -> void:
	_close_dialog()
	if why != "":
		_toast(why)
	career.save()
	show_hub(tab)


# ------------------------------------------------------------------ table / fixtures / cup

func _tab_table() -> void:
	if table_div < 0:
		table_div = career.clubs[career.user]["division"]
	var tabs := UI.hbox(6)
	for d in career.divisions.size():
		var dd := d
		var b := UI.button(career.division_names[d], func() -> void:
			table_div = dd
			show_hub("table"), 16, Vector2(0, 44))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if d == table_div:
			b.add_theme_stylebox_override("normal", UI._box(UI.ACCENT, 8))
		tabs.add_child(b)
	content.add_child(tabs)
	var list := UI.vbox(3)
	list.add_child(UI.row([["#", 34], ["Club", 0], ["P", 40, 1], ["W", 40, 1], ["D", 40, 1], ["L", 40, 1], ["GF", 46, 1], ["GA", 46, 1], ["GD", 50, 1], ["Pts", 54, 1]], Callable(), Color(0, 0, 0, 0), 15))
	var t := career.table(table_div)
	var n := t.size()
	for i in n:
		var r: Dictionary = t[i]
		var cid: int = r["club"]
		var tint := Color(0, 0, 0, 0)
		if i < 2 and table_div > 0:
			tint = Color(0.2, 0.6, 0.3, 0.25)
		elif i == 0:
			tint = Color(0.8, 0.65, 0.2, 0.25)
		if i >= n - 2 and table_div < career.divisions.size() - 1:
			tint = Color(0.7, 0.2, 0.2, 0.25)
		var col := UI.GOLD if cid == career.user else Color.WHITE
		list.add_child(UI.row([[str(i + 1), 34], [career.clubs[cid]["name"], 0, 0, col], [str(r["p"]), 40, 1], [str(r["w"]), 40, 1], [str(r["d"]), 40, 1],
			[str(r["l"]), 40, 1], [str(r["gf"]), 46, 1], [str(r["ga"]), 46, 1], ["%+d" % (r["gf"] - r["ga"]), 50, 1], [str(r["pts"]), 54, 1, col]],
			func() -> void: _club_card(cid), tint, 18))
	content.add_child(UI.scroll(list))
	content.add_child(UI.label("Top 2 go up, bottom 2 go down. Tap a club to see its squad.", 15, UI.MUTED))


func _tab_fixtures() -> void:
	var list := UI.vbox(3)
	var div: int = career.clubs[career.user]["division"]
	var cup_i := 0
	for i in career.calendar.size():
		var ev: Dictionary = career.calendar[i]
		var m := {}
		if ev["type"] == "league":
			for mm in career.fixtures[div][ev["round"]]:
				if mm["h"] == career.user or mm["a"] == career.user:
					m = mm
		else:
			var r: int = ev["round"]
			if career.cup["rounds"].size() > r:
				for mm in career.cup["rounds"][r]:
					if mm["h"] == career.user or mm["a"] == career.user:
						m = mm
		var label: String = "League %d" % (int(ev["round"]) + 1) if ev["type"] == "league" else "Cup: " + Career.CUP_ROUND_NAMES[ev["round"]]
		if m.is_empty():
			list.add_child(UI.row([["Wk %d" % (i + 1), 70], [label, 200, 0, UI.MUTED], ["—" if ev["type"] == "cup" else "", 0, 0, UI.MUTED]], Callable(), Color(0, 0, 0, 0), 17))
			continue
		var home: int = m["h"]
		var away: int = m["a"]
		var res := "vs"
		var col := Color.WHITE
		if m["hs"] >= 0:
			res = "%d - %d" % [m["hs"], m["as"]]
			var us: int = m["hs"] if home == career.user else m["as"]
			var them: int = m["as"] if home == career.user else m["hs"]
			col = Color("#5fd47a") if us > them else (Color("#e05050") if us < them else UI.GOLD)
			if us == them and m["pens"] >= 0:
				res += " (pens)"
				col = Color("#5fd47a") if m["pens"] == career.user else Color("#e05050")
		var tint := Color(1, 1, 1, 0.08) if i == career.week else Color(0, 0, 0, 0)
		list.add_child(UI.row([["Wk %d" % (i + 1), 70], [label, 200, 0, UI.MUTED], [career.clubs[home]["name"], 0, 2], [res, 110, 1, col], [career.clubs[away]["name"], 0]], Callable(), tint, 17))
	content.add_child(UI.label("Season %d — your fixtures" % career.year, 22))
	content.add_child(UI.scroll(list))


func _tab_cup() -> void:
	content.add_child(UI.label("The Cup — all 40 clubs, single matches, penalties if level", 20))
	var list := UI.vbox(3)
	var rounds: Array = career.cup["rounds"]
	if rounds.is_empty():
		var info := UI.label("The draw for the preliminary round hasn't been made yet. The lowest-ranked 16 clubs start there; everyone else joins in the round of 32.", 17, UI.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 300
		list.add_child(info)
	for r in range(rounds.size() - 1, -1, -1):
		list.add_child(UI.label(Career.CUP_ROUND_NAMES[r], 20, UI.GOLD))
		for m in rounds[r]:
			var res := "vs"
			if m["hs"] >= 0:
				res = "%d - %d" % [m["hs"], m["as"]]
				if m["hs"] == m["as"]:
					res += " p"
			var involved: bool = m["h"] == career.user or m["a"] == career.user
			var hcol := UI.GOLD if m["h"] == career.user else Color.WHITE
			var acol := UI.GOLD if m["a"] == career.user else Color.WHITE
			if m["hs"] >= 0:
				var w: int = m["h"] if m["hs"] > m["as"] else (m["a"] if m["as"] > m["hs"] else m["pens"])
				if w != m["h"]:
					hcol = Color(hcol, 0.45)
				if w != m["a"]:
					acol = Color(acol, 0.45)
			list.add_child(UI.row([[career.clubs[m["h"]]["name"], 0, 2, hcol], [res, 110, 1], [career.clubs[m["a"]]["name"], 0, 0, acol]], Callable(), Color(1, 1, 1, 0.08) if involved else Color(0, 0, 0, 0), 16))
	if career.cup.get("winner", -1) >= 0:
		list.add_child(UI.label("Winners: %s" % career.clubs[career.cup["winner"]]["name"], 22, UI.GOLD))
	content.add_child(UI.scroll(list))


func _club_card(cid: int) -> void:
	var c: Dictionary = career.clubs[cid]
	var v := UI.vbox(4)
	v.add_child(UI.label(c["name"], 28))
	v.add_child(UI.label("%s  ·  rating %d  ·  budget %s  ·  stadium %d" % [career.division_names[c["division"]], career.team_rating(cid), Ratings.money(c["budget"]), c["stadium"]], 16, UI.MUTED))
	var list := UI.vbox(3)
	var sq := career.squad(cid)
	sq.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Ratings.overall(a) > Ratings.overall(b))
	for p in sq:
		var pid: int = p["id"]
		var o := Ratings.overall(p)
		list.add_child(UI.row([[p["name"], 0], [p["pos"], 50], [str(p["age"]), 40, 1], [str(o), 46, 1, UI.rating_colour(o)], [Ratings.money(career.asking_price(pid)), 90, 2, UI.MUTED]],
			func() -> void: _player_card(pid), Color(0, 0, 0, 0), 16))
	var s := UI.scroll(list)
	s.custom_minimum_size = Vector2(620, 330)
	v.add_child(s)
	_dialog_node(v, [["CLOSE", func() -> void: _close_dialog()]])


# ------------------------------------------------------------------ transfers

func _tab_transfers() -> void:
	var top := UI.hbox(6)
	for f in ["ALL", "GK", "DEF", "MID", "FWD"]:
		var ff: String = f
		var b := UI.button(f, func() -> void:
			market_filter = ff
			show_hub("transfers"), 17, Vector2(70, 44))
		if f == market_filter:
			b.add_theme_stylebox_override("normal", UI._box(UI.ACCENT, 8))
		top.add_child(b)
	var fb := UI.button("FREE AGENTS" if not market_free else "ALL CLUBS", func() -> void:
		market_free = not market_free
		show_hub("transfers"), 17, Vector2(160, 44))
	top.add_child(fb)
	top.add_child(UI.spacer(0, true))
	var c: Dictionary = career.clubs[career.user]
	top.add_child(UI.label("Squad %d/%d" % [c["players"].size(), Career.MAX_SQUAD], 17, UI.MUTED))
	content.add_child(top)
	var cands: Array = []
	if market_free:
		for pid in career.free_agents:
			cands.append(career.players[pid])
	else:
		for pid in career.players:
			var p: Dictionary = career.players[pid]
			if p["club"] >= 0 and p["club"] != career.user:
				cands.append(p)
	if market_filter != "ALL":
		cands = cands.filter(func(p: Dictionary) -> bool: return p["pos"] == market_filter)
	# Show what's realistic first: affordable players, best first.
	var budget: int = c["budget"]
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aa := career.asking_price(a["id"]) <= budget
		var bb := career.asking_price(b["id"]) <= budget
		if aa != bb:
			return aa
		return Ratings.overall(a) > Ratings.overall(b))
	var list := UI.vbox(3)
	list.add_child(UI.row([["Name", 0], ["Pos", 50], ["Age", 44, 1], ["OVR", 50, 1], ["Club", 70], ["Price", 100, 2]], Callable(), Color(0, 0, 0, 0), 15))
	for p in cands.slice(0, 80):
		var pid: int = p["id"]
		var o := Ratings.overall(p)
		var price := career.asking_price(pid)
		var club_s: String = career.clubs[p["club"]]["short"] if p["club"] >= 0 else "free"
		list.add_child(UI.row([[p["name"], 0], [p["pos"], 50], [str(p["age"]), 44, 1], [str(o), 50, 1, UI.rating_colour(o)], [club_s, 70, 0, UI.MUTED],
			[Ratings.money(price), 100, 2, UI.GOLD if price <= budget else Color(1, 1, 1, 0.35)]],
			func() -> void: _player_card(pid), Color(0, 0, 0, 0), 17))
	content.add_child(UI.scroll(list))


# ------------------------------------------------------------------ club

func _tab_club() -> void:
	var cid := career.user
	var c: Dictionary = career.clubs[cid]
	var cols := UI.hbox(20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := UI.vbox(6)
	left.custom_minimum_size.x = 380
	left.add_child(UI.label("Finances", 22, UI.GOLD))
	for line in [
		["Budget", Ratings.money(c["budget"])],
		["Wage bill", Ratings.money(career.wage_bill(cid)) + " / week"],
		["Income this season", Ratings.money(c["season_income"])],
		["Wages this season", Ratings.money(c["season_wages"])],
		["Transfers this season", Ratings.money(c["season_transfers"])],
		["Last home gate", Ratings.money(c["last_income"])],
		["Stadium", "%d seats" % c["stadium"]],
		["Reputation", "%d / 99" % c["reputation"]],
	]:
		left.add_child(UI.row([[line[0], 0, 0, UI.MUTED], [line[1], 170, 2]], Callable(), Color(0, 0, 0, 0), 17))
	left.add_child(UI.label("Honours", 22, UI.GOLD))
	if career.history.is_empty():
		left.add_child(UI.label("No seasons finished yet.", 16, UI.MUTED))
	for h in career.history.slice(maxi(0, career.history.size() - 6)):
		var champs: Array = h["champions"]
		var cupw: int = h["cup"]
		left.add_child(UI.label("%d: %s  ·  Cup: %s" % [h["year"], career.clubs[champs[0]]["short"], career.clubs[cupw]["short"] if cupw >= 0 else "-"], 15))
	cols.add_child(left)
	var right := UI.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UI.label("News", 22, UI.GOLD))
	var nl := UI.vbox(4)
	for n in career.news:
		var l := UI.label(n, 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.add_child(l)
	right.add_child(UI.scroll(nl))
	cols.add_child(right)
	content.add_child(cols)


# ------------------------------------------------------------------ playing

func _play_career_match() -> void:
	var m := career.user_match()
	if m.is_empty():
		return
	var home: int = m["h"]
	var away: int = m["a"]
	var hc: Dictionary = career.clubs[home]
	var ac: Dictionary = career.clubs[away]
	var away_uses_away: bool = Career.kits_clash(hc["home"], ac["home"])
	var home_team := career.match_team(home, false)
	var away_team := career.match_team(away, away_uses_away)
	var user_home := home == career.user
	var teams: Array = [home_team, away_team] if user_home else [away_team, home_team]
	layer.visible = false
	match_node = MATCH_SCENE.instantiate()
	match_node.configure({"teams": teams})
	match_node.finished.connect(func(r: Dictionary) -> void:
		match_node.queue_free()
		match_node = null
		layer.visible = true
		if r.get("aborted", false):
			show_hub("match")
			return
		var sc: Array = r["score"]
		var scorers: Array = []
		for s in r["scorers"]:
			var side: int = s[0]
			var pid: int = s[1]
			if pid < 0:
				continue
			var club: int = career.user if side == 0 else (away if user_home else home)
			scorers.append([club, pid])
		_advance({"hs": sc[0] if user_home else sc[1], "as": sc[1] if user_home else sc[0],
			"scorers": scorers, "energy": r["energy"]}))
	add_child(match_node)


func _advance(user_result: Dictionary) -> void:
	var y := career.year
	career.advance(user_result)
	_pending_season_end = career.year != y
	career.save()
	show_results()


func show_results() -> void:
	var m := _frame()
	var v := UI.vbox(10)
	m.add_child(v)
	var lw: Dictionary = career.last_week
	var ev: Dictionary = lw["event"]
	v.add_child(UI.label(("League round %d" % (int(ev["round"]) + 1)) if ev["type"] == "league" else "Cup — " + Career.CUP_ROUND_NAMES[ev["round"]], 26, UI.GOLD))
	var um: Dictionary = lw["user_match"]
	if not um.is_empty():
		var box := UI.vbox(4)
		var line := UI.hbox(20)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_child(UI.label(career.clubs[um["h"]]["name"], 30))
		line.add_child(UI.label("%d - %d" % [um["hs"], um["as"]], 40, UI.GOLD))
		line.add_child(UI.label(career.clubs[um["a"]]["name"], 30))
		box.add_child(line)
		if um["hs"] == um["as"] and um["pens"] >= 0:
			box.add_child(UI.label("%s win on penalties" % career.clubs[um["pens"]]["name"], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		var names: Array = []
		for s in um["scorers"]:
			var pid: int = s[1]
			if career.players.has(pid):
				names.append("%s (%s)" % [career.players[pid]["name"], career.clubs[s[0]]["short"]])
		if not names.is_empty():
			var l := UI.label("Goals: " + ", ".join(names), 17, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(l)
		v.add_child(UI.panel(box))
	var list := UI.vbox(3)
	var div: int = career.clubs[career.user]["division"]
	for mm in lw["matches"]:
		var in_div: bool = career.clubs[mm["h"]]["division"] == div or career.clubs[mm["a"]]["division"] == div
		if ev["type"] == "league" and not in_div:
			continue
		var res := "%d - %d" % [mm["hs"], mm["as"]]
		if mm["hs"] == mm["as"] and mm["pens"] >= 0:
			res += " p"
		list.add_child(UI.row([[career.clubs[mm["h"]]["name"], 0, 2], [res, 110, 1, UI.GOLD], [career.clubs[mm["a"]]["name"], 0]], Callable(), Color(0, 0, 0, 0), 17))
	v.add_child(UI.label("Other results" if ev["type"] == "league" else "All results", 18, UI.MUTED))
	v.add_child(UI.scroll(list))
	var b := UI.accent_button("CONTINUE", func() -> void:
		if _pending_season_end:
			_pending_season_end = false
			show_season_end()
		else:
			show_hub("match"))
	b.custom_minimum_size = Vector2(300, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)


func show_season_end() -> void:
	var s := career.season_summary
	var m := _frame()
	var v := UI.vbox(8)
	m.add_child(v)
	v.add_child(UI.label("Season %d is over" % s["year"], 34, UI.GOLD))
	var c: Dictionary = career.clubs[career.user]
	var finish := "You finished %s in the %s (prize %s)." % [_ordinal(s["user_pos"]), career.division_names[s["user_div"]], Ratings.money(s["prize"])]
	v.add_child(UI.label(finish, 22))
	if s["promoted"].has(career.user):
		v.add_child(UI.label("PROMOTED to the %s!" % career.division_names[c["division"]], 26, Color("#5fd47a")))
	elif s["relegated"].has(career.user):
		v.add_child(UI.label("Relegated to the %s." % career.division_names[c["division"]], 26, Color("#e05050")))
	var list := UI.vbox(4)
	for d in s["champions"].size():
		list.add_child(UI.row([[career.division_names[d] + " champions", 280, 0, UI.MUTED], [career.clubs[s["champions"][d]]["name"], 0]], Callable(), Color(0, 0, 0, 0), 18))
	if s["cup"] >= 0:
		list.add_child(UI.row([["Cup winners", 280, 0, UI.MUTED], [career.clubs[s["cup"]]["name"], 0]], Callable(), Color(0, 0, 0, 0), 18))
	var up: Array = []
	for cid in s["promoted"]:
		up.append(career.clubs[cid]["short"])
	var down: Array = []
	for cid in s["relegated"]:
		down.append(career.clubs[cid]["short"])
	list.add_child(UI.row([["Promoted", 280, 0, UI.MUTED], [", ".join(up), 0]], Callable(), Color(0, 0, 0, 0), 17))
	list.add_child(UI.row([["Relegated", 280, 0, UI.MUTED], [", ".join(down), 0]], Callable(), Color(0, 0, 0, 0), 17))
	if not s["retired"].is_empty():
		list.add_child(UI.row([["Retired from your squad", 280, 0, UI.MUTED], [", ".join(s["retired"]), 0]], Callable(), Color(0, 0, 0, 0), 17))
	if not s["youth"].is_empty():
		list.add_child(UI.row([["Youth players joining", 280, 0, UI.MUTED], [", ".join(s["youth"]), 0]], Callable(), Color(0, 0, 0, 0), 17))
	list.add_child(UI.label("Everyone is a year older: young players improved, veterans lost a step.", 16, UI.MUTED))
	v.add_child(UI.scroll(list))
	var b := UI.accent_button("START SEASON %d" % career.year, func() -> void: show_hub("match"))
	b.custom_minimum_size = Vector2(340, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)


func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


# ------------------------------------------------------------------ dialogs

func _dialog(title: String, text: String, actions: Array) -> void:
	var v := UI.vbox(10)
	v.add_child(UI.label(title, 28))
	var l := UI.label(text, 19)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	v.add_child(l)
	_dialog_node(v, actions)


func _dialog_node(body: Control, actions: Array) -> void:
	_close_dialog()
	dialog = Control.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	var v := UI.vbox(14)
	v.add_child(body)
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	for i in actions.size():
		var a: Array = actions[i]
		var b := UI.accent_button(a[0], a[1], 20, Vector2(150, 54)) if i == 0 and actions.size() > 1 else UI.button(a[0], a[1], 20, Vector2(150, 54))
		row.add_child(b)
	v.add_child(row)
	var p := UI.panel(v)
	p.add_theme_stylebox_override("panel", UI._box(Color("#1f3a28"), 12, 22))
	center.add_child(p)
	root.add_child(dialog)


func _close_dialog() -> void:
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()
	dialog = null


func _toast(text: String) -> void:
	var l := UI.label(text, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var p := UI.panel(l)
	p.add_theme_stylebox_override("panel", UI._box(Color(0.5, 0.15, 0.15, 0.95), 10, 16))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	p.position.y -= 90
	root.add_child(p)
	p.reset_size()
	p.position.x = (root.size.x - p.size.x) * 0.5
	var tw := p.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
