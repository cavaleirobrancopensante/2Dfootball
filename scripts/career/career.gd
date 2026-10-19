class_name Career
extends RefCounted
## A manager career: four divisions with promotion and relegation, a cup,
## seasons of 18 league rounds plus 6 cup rounds, player condition and
## recovery by age, development, ageing, retirements, youth, finances and
## transfers. All state lives in plain dictionaries so it saves with store_var.

const SAVE_PATH := "user://career.save"
const DB_PATH := "res://data/database.json"
const TICKET := 15.0
const TV_PER_WEEK := [180000, 55000, 16000, 5000]
const PRIZE := [5000000, 1500000, 500000, 150000]
const CUP_PRIZE := 1000000
const CUP_ROUND_NAMES := ["Preliminary round", "Round of 32", "Round of 16", "Quarter-final", "Semi-final", "Final"]
const MIN_SQUAD := 14
const MAX_SQUAD := 28
const LINEUP := 11
const SAVE_VERSION := 2

var rng := RandomNumberGenerator.new()

var year := 2026
var week := 0                    # index into calendar
var calendar: Array = []         # [{type: "league"/"cup", round: int}]
var divisions: Array = []        # Array of Array[int] club ids, index 0 = top
var division_names: Array = []
var clubs: Array = []            # club dictionaries, index = id
var players: Dictionary = {}     # id -> player dictionary
var free_agents: Array = []
var fixtures: Array = []         # per division: Array of rounds: Array of match dicts
var cup: Dictionary = {}
var history: Array = []
var news: Array = []
var user := -1
var next_pid := 0
var last_week: Dictionary = {}   # results of the most recent week, for the results screen
var season_summary: Dictionary = {}


# ------------------------------------------------------------------ creation

func new_from_database() -> void:
	rng.randomize()
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	var db: Dictionary = JSON.parse_string(f.get_as_text())
	year = int(db.get("start_year", 2026))
	for pj in db["players"]:
		var p: Dictionary = pj
		var id: int = int(p["id"])
		var stats := {}
		for a in Ratings.ATTRS:
			stats[a] = clampi(int(p["stats"].get(a, 50)), 1, 99)
		var look: Dictionary = p.get("look", {})
		players[id] = {
			"id": id, "name": str(p["name"]), "nation": str(p.get("nation", "")), "age": int(p["age"]),
			"pos": str(p["pos"]), "stats": stats, "potential": int(p.get("potential", 60)),
			"look": {"skin": str(look.get("skin", "#d9a27a")), "hair": str(look.get("hair", "short")),
				"hair_colour": str(look.get("hair_colour", "#2e1e14"))},
			"club": -1, "condition": 100.0, "injury": 0,
			"s_apps": 0, "s_goals": 0, "apps": 0, "goals": 0,
		}
		next_pid = maxi(next_pid, id + 1)
	for cj in db["clubs"]:
		var c: Dictionary = cj
		var squad: Array = []
		for pid in c["players"]:
			squad.append(int(pid))
			players[int(pid)]["club"] = int(c["id"])
		clubs.append({
			"id": int(c["id"]), "name": str(c["name"]), "short": str(c["short"]),
			"reputation": int(c["reputation"]), "budget": int(c["budget"]), "stadium": int(c["stadium"]),
			"home": c["home"], "away": c["away"], "gk": str(c["gk"]),
			"players": squad, "lineup": [], "formation": "2-2", "division": 0,
			"last_income": 0, "season_income": 0, "season_wages": 0, "season_transfers": 0,
		})
	for l in db["leagues"]:
		var ids: Array = []
		for cid in l["clubs"]:
			ids.append(int(cid))
		divisions.append(ids)
		division_names.append(str(l["name"]))
	for d in divisions.size():
		for cid in divisions[d]:
			clubs[cid]["division"] = d
	for pid in db.get("free_agents", []):
		free_agents.append(int(pid))
	for c in clubs:
		var fs: Array = Ratings.FORMATIONS.keys()
		c["formation"] = fs[rng.randi() % fs.size()]
		auto_lineup(c["id"])


func start(club_id: int) -> void:
	user = club_id
	_new_season()
	add_news("You take charge of %s. The board expects a solid season." % clubs[user]["name"])


# ------------------------------------------------------------------ season setup

func _new_season() -> void:
	week = 0
	fixtures = []
	for d in divisions.size():
		fixtures.append(_round_robin(divisions[d]))
	calendar = []
	var cup_after := [2, 5, 8, 11, 14, 17]
	var ci := 0
	for r in 18:
		calendar.append({"type": "league", "round": r})
		if ci < cup_after.size() and r == cup_after[ci]:
			calendar.append({"type": "cup", "round": ci})
			ci += 1
	_setup_cup()
	for pid in players:
		var p: Dictionary = players[pid]
		p["s_apps"] = 0
		p["s_goals"] = 0
	for c in clubs:
		c["season_income"] = 0
		c["season_wages"] = 0
		c["season_transfers"] = 0


func _round_robin(ids: Array) -> Array:
	var teams := ids.duplicate()
	teams.shuffle()
	if teams.size() % 2 == 1:
		teams.append(-1)
	var n := teams.size()
	var rounds: Array = []
	for r in n - 1:
		var round_matches: Array = []
		for i in n / 2:
			var a: int = teams[i]
			var b: int = teams[n - 1 - i]
			if a == -1 or b == -1:
				continue
			if (r + i) % 2 == 0:
				round_matches.append(_match(a, b))
			else:
				round_matches.append(_match(b, a))
		rounds.append(round_matches)
		# rotate all but the first
		var last: int = teams.pop_back()
		teams.insert(1, last)
	var second: Array = []
	for rm in rounds:
		var mirrored: Array = []
		for m in rm:
			mirrored.append(_match(m["a"], m["h"]))
		second.append(mirrored)
	return rounds + second


func _match(h: int, a: int) -> Dictionary:
	return {"h": h, "a": a, "hs": -1, "as": -1, "pens": -1, "scorers": []}


func _setup_cup() -> void:
	# Lowest 16 clubs play a preliminary round; the rest join in the round of 32.
	var order: Array = []
	for d in divisions.size():
		var ids: Array = divisions[d].duplicate()
		ids.sort_custom(func(a: int, b: int) -> bool: return clubs[a]["reputation"] > clubs[b]["reputation"])
		order += ids
	var prelim: Array = order.slice(order.size() - 16)
	var byes: Array = order.slice(0, order.size() - 16)
	cup = {"round": 0, "rounds": [], "byes": byes, "alive": prelim.duplicate(), "winner": -1}


func _draw_cup_round() -> void:
	var entrants: Array = cup["alive"].duplicate()
	if cup["round"] == 1:
		entrants += cup["byes"]
	entrants.shuffle()
	var matches: Array = []
	for i in range(0, entrants.size() - 1, 2):
		matches.append(_match(entrants[i], entrants[i + 1]))
	cup["rounds"].append(matches)


# ------------------------------------------------------------------ queries

func current_event() -> Dictionary:
	return calendar[week] if week < calendar.size() else {}


func event_name(ev: Dictionary) -> String:
	if ev.is_empty():
		return ""
	if ev["type"] == "league":
		return "%s — round %d" % [division_names[clubs[user]["division"]], int(ev["round"]) + 1]
	return "Cup — %s" % CUP_ROUND_NAMES[int(ev["round"])]


## The user's match this week, or {} if the user has no match (e.g. out of the cup).
func user_match() -> Dictionary:
	var ev := current_event()
	if ev.is_empty():
		return {}
	for m in _event_matches(ev):
		if m["h"] == user or m["a"] == user:
			return m
	return {}


func _event_matches(ev: Dictionary) -> Array:
	if ev["type"] == "league":
		var all: Array = []
		for d in divisions.size():
			all += fixtures[d][ev["round"]]
		return all
	var r: int = ev["round"]
	if cup["rounds"].size() <= r:
		_draw_cup_round()
	return cup["rounds"][r]


func table(div: int) -> Array:
	var rows := {}
	for cid in divisions[div]:
		rows[cid] = {"club": cid, "p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0}
	for rnd in fixtures[div]:
		for m in rnd:
			if m["hs"] < 0:
				continue
			var h: Dictionary = rows[m["h"]]
			var a: Dictionary = rows[m["a"]]
			var hs: int = m["hs"]
			var as_: int = m["as"]
			h["p"] += 1; a["p"] += 1
			h["gf"] += hs; h["ga"] += as_; a["gf"] += as_; a["ga"] += hs
			if hs > as_:
				h["w"] += 1; a["l"] += 1; h["pts"] += 3
			elif hs < as_:
				a["w"] += 1; h["l"] += 1; a["pts"] += 3
			else:
				h["d"] += 1; a["d"] += 1; h["pts"] += 1; a["pts"] += 1
	var list: Array = rows.values()
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["pts"] != y["pts"]:
			return x["pts"] > y["pts"]
		var gx: int = x["gf"] - x["ga"]
		var gy: int = y["gf"] - y["ga"]
		if gx != gy:
			return gx > gy
		if x["gf"] != y["gf"]:
			return x["gf"] > y["gf"]
		return clubs[x["club"]]["name"] < clubs[y["club"]]["name"])
	return list


func squad(cid: int) -> Array:
	var list: Array = []
	for pid in clubs[cid]["players"]:
		list.append(players[pid])
	return list


func roles_for(cid: int) -> Array:
	return ["GK"] + Ratings.roles(clubs[cid]["formation"])


func lineup_players(cid: int) -> Array:
	var list: Array = []
	for pid in clubs[cid]["lineup"]:
		list.append(players[pid])
	return list


func strength(cid: int) -> Vector2:
	return Ratings.team_strength(lineup_players(cid), roles_for(cid))


func team_rating(cid: int) -> int:
	var s := strength(cid)
	return int(round((s.x + s.y) * 0.5))


func wage_bill(cid: int) -> int:
	var t := 0
	for pid in clubs[cid]["players"]:
		t += Ratings.wage(players[pid])
	return t


func add_news(t: String) -> void:
	news.push_front("%d · wk %d — %s" % [year, week + 1, t])
	if news.size() > 60:
		news.resize(60)


# ------------------------------------------------------------------ lineups

## Picks the best available keeper and outfield players for the formation.
func auto_lineup(cid: int) -> void:
	var c: Dictionary = clubs[cid]
	var roles: Array = ["GK"] + Ratings.roles(c["formation"])
	var chosen: Array = []
	for role in roles:
		var best := -1
		var best_score := -INF
		for pid in c["players"]:
			if chosen.has(pid):
				continue
			var p: Dictionary = players[pid]
			if p["injury"] > 0:
				continue
			if (role == "GK") != (p["pos"] == "GK"):
				continue
			var sc := Ratings.overall(p, role) * (0.55 + 0.45 * float(p["condition"]) / 100.0)
			if sc > best_score:
				best_score = sc
				best = pid
		if best == -1:
			# Nobody fits: take anyone fit (even an injured player as a last resort).
			for pid in c["players"]:
				if not chosen.has(pid):
					best = pid
					break
		if best != -1:
			chosen.append(best)
	c["lineup"] = chosen


## Makes sure a lineup is legal (11 distinct, fit players, keeper first).
func validate_lineup(cid: int) -> void:
	var c: Dictionary = clubs[cid]
	var ok: bool = c["lineup"].size() == LINEUP
	var seen := {}
	for i in c["lineup"].size():
		var pid: int = c["lineup"][i]
		if not players.has(pid) or players[pid]["club"] != cid or players[pid]["injury"] > 0 or seen.has(pid):
			ok = false
		seen[pid] = true
	if ok and players[c["lineup"][0]]["pos"] != "GK":
		ok = false
	if not ok:
		auto_lineup(cid)


# ------------------------------------------------------------------ playing a week

## Plays every match of the current event. If the user played their match,
## pass its result: {hs, as, scorers: [[club_id, player_id]], energy: {pid: 0..1}}.
func advance(user_result := {}) -> void:
	var ev := current_event()
	if ev.is_empty():
		return
	for c in clubs:
		validate_lineup(c["id"])
	var matches := _event_matches(ev)
	var played_by: Dictionary = {}     # pid -> energy used (for condition)
	last_week = {"event": ev.duplicate(), "matches": [], "user_match": {}}
	for m in matches:
		var is_user: bool = m["h"] == user or m["a"] == user
		if is_user and not user_result.is_empty():
			m["hs"] = user_result["hs"]
			m["as"] = user_result["as"]
			m["scorers"] = user_result.get("scorers", [])
			for pid in user_result.get("energy", {}):
				played_by[int(pid)] = float(user_result["energy"][pid])
			for cid in [m["h"], m["a"]]:
				for pid in clubs[cid]["lineup"]:
					if not played_by.has(pid):
						played_by[pid] = -1.0
		else:
			_simulate(m)
			for cid in [m["h"], m["a"]]:
				for pid in clubs[cid]["lineup"]:
					played_by[pid] = -1.0
		if ev["type"] == "cup" and m["hs"] == m["as"]:
			# Penalties, slightly favouring the stronger side.
			var sh := team_rating(m["h"])
			var sa := team_rating(m["a"])
			m["pens"] = m["h"] if rng.randf() < 0.5 + (sh - sa) * 0.01 else m["a"]
		for sc in m["scorers"]:
			var pid: int = sc[1]
			if players.has(pid):
				players[pid]["s_goals"] += 1
				players[pid]["goals"] += 1
		_gate_money(m["h"])
		last_week["matches"].append(m)
		if is_user:
			last_week["user_match"] = m
	_after_matches(played_by)
	if ev["type"] == "cup":
		_advance_cup(matches)
	_weekly_money()
	_ai_transfers()
	week += 1
	if week >= calendar.size():
		_end_season()


func _simulate(m: Dictionary) -> void:
	var h: int = m["h"]
	var a: int = m["a"]
	var sh := strength(h)
	var sa := strength(a)
	var lh := 1.45 * exp((sh.x - sa.y) / 14.0) * 1.12
	var la := 1.45 * exp((sa.x - sh.y) / 14.0) / 1.05
	m["hs"] = _poisson(clampf(lh, 0.2, 4.2))
	m["as"] = _poisson(clampf(la, 0.2, 4.2))
	var scorers: Array = []
	for i in m["hs"]:
		scorers.append([h, _pick_scorer(h)])
	for i in m["as"]:
		scorers.append([a, _pick_scorer(a)])
	m["scorers"] = scorers


func _poisson(l: float) -> int:
	var L := exp(-l)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= L:
			return k
		k += 1
	return k


func _pick_scorer(cid: int) -> int:
	var roles := roles_for(cid)
	var lineup: Array = clubs[cid]["lineup"]
	var total := 0.0
	var weights: Array = []
	for i in lineup.size():
		var w: float = {"GK": 0.0, "DEF": 0.6, "MID": 1.6, "FWD": 3.5}[roles[i]]
		w *= Ratings.stat(players[lineup[i]], "shooting") / 60.0
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return lineup[i]
	return lineup[lineup.size() - 1]


func _after_matches(played_by: Dictionary) -> void:
	for pid in played_by:
		var p: Dictionary = players[pid]
		p["s_apps"] += 1
		p["apps"] += 1
		var e: float = played_by[pid]
		var drop: float
		if e >= 0.0:
			drop = (1.0 - e) * 60.0 + 6.0   # measured on the pitch
		else:
			drop = lerpf(38.0, 16.0, Ratings.stat(p, "stamina") / 100.0) + rng.randf_range(-4, 4)
		p["condition"] = maxf(p["condition"] - drop, 20.0)
		var injury_chance := 0.025 + (0.015 if p["age"] >= 30 else 0.0) + (0.02 if p["condition"] < 45.0 else 0.0)
		if rng.randf() < injury_chance:
			p["injury"] = rng.randi_range(1, 4) + (1 if p["age"] >= 31 else 0)
			if p["club"] == user:
				add_news("%s is injured for %d week%s." % [p["name"], p["injury"], "" if p["injury"] == 1 else "s"])
	# Everyone recovers through the week; younger players bounce back faster.
	for pid in players:
		var p: Dictionary = players[pid]
		var just_hurt: bool = played_by.has(pid) and p["injury"] > 0
		if p["injury"] > 0 and not just_hurt:
			p["injury"] -= 1
		p["condition"] = minf(100.0, p["condition"] + recovery(p))


static func recovery(p: Dictionary) -> float:
	var age: int = p["age"]
	if age <= 21:
		return 34.0
	if age <= 25:
		return 30.0
	if age <= 29:
		return 26.0
	if age <= 32:
		return 20.0
	return 15.0


func _advance_cup(matches: Array) -> void:
	var winners: Array = []
	for m in matches:
		var w: int
		if m["hs"] > m["as"]:
			w = m["h"]
		elif m["as"] > m["hs"]:
			w = m["a"]
		else:
			w = m["pens"]
		winners.append(w)
		if m["h"] == user or m["a"] == user:
			if w == user:
				add_news("Through to the next cup round!" if cup["round"] < 5 else "CUP WINNERS!")
			else:
				add_news("Knocked out of the cup by %s." % clubs[w if w != user else (m["a"] if m["h"] == user else m["h"])]["name"])
	cup["alive"] = winners
	cup["round"] += 1
	if winners.size() == 1:
		cup["winner"] = winners[0]
		clubs[winners[0]]["budget"] += CUP_PRIZE


# ------------------------------------------------------------------ money

func _gate_money(home: int) -> void:
	var c: Dictionary = clubs[home]
	var fill := clampf(0.35 + c["reputation"] / 200.0 + rng.randf_range(-0.08, 0.08), 0.25, 1.0)
	var gate := int(c["stadium"] * fill * TICKET)
	c["budget"] += gate
	c["season_income"] += gate
	c["last_income"] = gate


func _weekly_money() -> void:
	for c in clubs:
		var wages := wage_bill(c["id"])
		var tv: int = TV_PER_WEEK[c["division"]]
		c["budget"] += tv - wages
		c["season_income"] += tv
		c["season_wages"] += wages


# ------------------------------------------------------------------ transfers

func asking_price(pid: int) -> int:
	var p: Dictionary = players[pid]
	if p["club"] == -1:
		return Ratings.round_money(Ratings.value(p) * 0.3)
	var c: Dictionary = clubs[p["club"]]
	var mult := 1.25
	if c["lineup"].has(pid):
		mult = 1.7
	return Ratings.round_money(Ratings.value(p) * mult)


## Returns "" on success or the reason it failed.
func can_buy(pid: int) -> String:
	var p: Dictionary = players[pid]
	if p["club"] == user:
		return "Already in your squad."
	if clubs[user]["players"].size() >= MAX_SQUAD:
		return "Your squad is full (%d players)." % MAX_SQUAD
	if asking_price(pid) > clubs[user]["budget"]:
		return "Not enough money."
	if p["club"] != -1 and clubs[p["club"]]["players"].size() <= 16:
		return "%s won't sell: their squad is too small." % clubs[p["club"]]["name"]
	return ""


func buy(pid: int) -> String:
	var why := can_buy(pid)
	if why != "":
		return why
	var price := asking_price(pid)
	_move_player(pid, user, price)
	add_news("Signed %s for %s." % [players[pid]["name"], Ratings.money(price)])
	return ""


## An offer for one of the user's players from an AI club, or {} if nobody bites.
func sale_offer(pid: int) -> Dictionary:
	var p: Dictionary = players[pid]
	var v := Ratings.value(p)
	var ovr := Ratings.overall(p)
	var candidates: Array = []
	for c in clubs:
		if c["id"] == user or c["players"].size() >= MAX_SQUAD - 1:
			continue
		if c["budget"] < v * 0.8:
			continue
		var avg := team_rating(c["id"])
		if absf(avg - ovr) < 14:
			candidates.append(c["id"])
	if candidates.is_empty():
		return {}
	var buyer: int = candidates[rng.randi() % candidates.size()]
	return {"club": buyer, "price": Ratings.round_money(v * rng.randf_range(0.8, 1.05))}


func sell(pid: int, offer: Dictionary) -> String:
	if clubs[user]["players"].size() <= MIN_SQUAD:
		return "You need at least %d players." % MIN_SQUAD
	var name: String = players[pid]["name"]
	_move_player(pid, offer["club"], offer["price"])
	add_news("Sold %s to %s for %s." % [name, clubs[offer["club"]]["name"], Ratings.money(offer["price"])])
	return ""


func release(pid: int) -> String:
	if clubs[user]["players"].size() <= MIN_SQUAD:
		return "You need at least %d players." % MIN_SQUAD
	add_news("Released %s." % players[pid]["name"])
	_move_player(pid, -1, 0)
	return ""


func _move_player(pid: int, to: int, price: int) -> void:
	var p: Dictionary = players[pid]
	var from: int = p["club"]
	if from == -1:
		free_agents.erase(pid)
	else:
		clubs[from]["players"].erase(pid)
		clubs[from]["lineup"].erase(pid)
		clubs[from]["budget"] += price
		clubs[from]["season_transfers"] += price
	if to == -1:
		free_agents.append(pid)
	else:
		clubs[to]["players"].append(pid)
		clubs[to]["budget"] -= price
		clubs[to]["season_transfers"] -= price
	p["club"] = to
	if from != -1:
		validate_lineup(from)


func _ai_transfers() -> void:
	for c in clubs:
		var cid: int = c["id"]
		if cid == user:
			continue
		var n: int = c["players"].size()
		if c["budget"] < 0 and n > 18:
			# In debt: let the best-paid squad player (not a starter) go.
			var worst := -1
			var wv := -1
			for pid in c["players"]:
				if c["lineup"].has(pid):
					continue
				var w := Ratings.wage(players[pid])
				if w > wv:
					wv = w
					worst = pid
			if worst != -1:
				var buyer := -1
				for o in clubs:
					if o["id"] != cid and o["id"] != user and o["budget"] > Ratings.value(players[worst]) and o["players"].size() < 22:
						buyer = o["id"]
						break
				_move_player(worst, buyer, Ratings.round_money(Ratings.value(players[worst]) * 0.8) if buyer != -1 else 0)
			continue
		if n < 18 and rng.randf() < 0.5:
			# Sign the best free agent they can afford.
			var best := -1
			var bo := -1
			for pid in free_agents:
				var price := asking_price(pid)
				var o := Ratings.overall(players[pid])
				if price <= c["budget"] and o > bo:
					bo = o
					best = pid
			if best != -1:
				_move_player(best, cid, asking_price(best))
		elif n < MAX_SQUAD - 2 and rng.randf() < 0.025:
			# Occasionally buy a better player from a smaller club.
			var target := -1
			var weakest := 999
			for pid in c["lineup"]:
				weakest = mini(weakest, Ratings.overall(players[pid]))
			for tries in 12:
				var other: Dictionary = clubs[rng.randi() % clubs.size()]
				if other["id"] == cid or other["id"] == user or other["players"].size() <= 17:
					continue
				if other["division"] < c["division"]:
					continue
				var pid: int = other["players"][rng.randi() % other["players"].size()]
				if Ratings.overall(players[pid]) > weakest + 3 and asking_price(pid) <= c["budget"] * 0.6:
					target = pid
					break
			if target != -1:
				var seller: int = players[target]["club"]
				_move_player(target, cid, asking_price(target))
				if seller == user:
					pass   # never happens: the user's players aren't targeted
		if rng.randf() < 0.3:
			auto_lineup(cid)


# ------------------------------------------------------------------ end of season

func _end_season() -> void:
	var summary := {"year": year, "champions": [], "promoted": [], "relegated": [], "retired": [], "youth": [],
		"cup": cup.get("winner", -1), "user_div": clubs[user]["division"], "user_pos": 0, "prize": 0}
	var tables: Array = []
	for d in divisions.size():
		tables.append(table(d))
	for d in divisions.size():
		var t: Array = tables[d]
		summary["champions"].append(t[0]["club"])
		for i in t.size():
			var cid: int = t[i]["club"]
			var prize := int(PRIZE[d] * maxf(0.1, 1.0 - i * 0.1))
			clubs[cid]["budget"] += prize
			if cid == user:
				summary["user_pos"] = i + 1
				summary["prize"] = prize
	# Promotion / relegation: two up, two down between each pair of divisions.
	for d in range(divisions.size() - 1):
		var upper: Array = tables[d]
		var lower: Array = tables[d + 1]
		var down: Array = [upper[upper.size() - 1]["club"], upper[upper.size() - 2]["club"]]
		var up: Array = [lower[0]["club"], lower[1]["club"]]
		for cid in down:
			divisions[d].erase(cid)
			divisions[d + 1].append(cid)
			clubs[cid]["division"] = d + 1
			clubs[cid]["reputation"] = maxi(clubs[cid]["reputation"] - 5, 10)
			summary["relegated"].append(cid)
		for cid in up:
			divisions[d + 1].erase(cid)
			divisions[d].append(cid)
			clubs[cid]["division"] = d
			clubs[cid]["reputation"] = mini(clubs[cid]["reputation"] + 5, 99)
			summary["promoted"].append(cid)
	history.append({"year": year, "champions": summary["champions"], "cup": summary["cup"]})

	_develop_players(summary)
	_youth_intake(summary)
	for c in clubs:
		if c["id"] != user:
			_trim_squad(c["id"])
		if c["id"] != user:
			auto_lineup(c["id"])
		else:
			validate_lineup(c["id"])
	_tidy_free_agents()
	season_summary = summary
	year += 1
	_new_season()
	add_news("Season %d begins in the %s." % [year, division_names[clubs[user]["division"]]])


func _develop_players(summary: Dictionary) -> void:
	var gone: Array = []
	for pid in players:
		var p: Dictionary = players[pid]
		var age: int = p["age"]
		var ovr := Ratings.overall(p)
		var pot: int = p["potential"]
		var weights: Dictionary = Ratings.ROLE_WEIGHTS[p["pos"]]
		# Growth toward potential, faster when young and playing.
		var rate := 0.0
		if age <= 21:
			rate = 0.35
		elif age <= 24:
			rate = 0.22
		elif age <= 27:
			rate = 0.08
		var played := clampf(float(p["s_apps"]) / 18.0, 0.0, 1.0)
		var growth := maxf(pot - ovr, 0) * rate * (0.6 + 0.6 * played)
		for a in Ratings.ATTRS:
			var s: float = p["stats"][a]
			var focus := 1.6 if weights.has(a) else 0.6
			s += growth * focus * rng.randf_range(0.5, 1.3)
			# Decline: legs first, then everything.
			var start := 33 if p["pos"] == "GK" else 30
			if age >= start and a in ["pace", "acceleration", "stamina"]:
				s -= rng.randf_range(1.0, 4.0) * (1.0 + (age - start) * 0.4)
			elif age >= start + 2:
				s -= rng.randf_range(0.0, 2.5)
			p["stats"][a] = clampi(int(round(s)), 1, 99)
		p["age"] = age + 1
		p["condition"] = 100.0
		# Retirement
		var ret_age := 34 if p["pos"] != "GK" else 36
		if p["age"] >= ret_age and rng.randf() < 0.25 + (p["age"] - ret_age) * 0.25:
			gone.append(pid)
	for pid in gone:
		var p: Dictionary = players[pid]
		if p["club"] == user:
			summary["retired"].append(p["name"])
		if p["club"] != -1:
			clubs[p["club"]]["players"].erase(pid)
			clubs[p["club"]]["lineup"].erase(pid)
		else:
			free_agents.erase(pid)
		players.erase(pid)


func _youth_intake(summary: Dictionary) -> void:
	var names := _name_pool()
	for c in clubs:
		var tier: int = c["division"]
		var base: float = [70.0, 60.0, 51.0, 43.0][tier] - 14.0 + rng.randf_range(-4, 4)
		for i in 3:
			if c["players"].size() >= MAX_SQUAD:
				break
			var pos: String = ["GK", "DEF", "MID", "FWD", "FWD", "MID", "DEF"][rng.randi() % 7]
			var p := _make_youth(pos, base, names)
			p["club"] = c["id"]
			players[p["id"]] = p
			c["players"].append(p["id"])
			if c["id"] == user:
				summary["youth"].append("%s (%s, %d, potential %d)" % [p["name"], pos, p["age"], p["potential"]])
	while free_agents.size() < 60:
		var pos: String = ["GK", "DEF", "MID", "FWD"][rng.randi() % 4]
		var p := _make_youth(pos, rng.randf_range(38, 60), names)
		p["age"] = rng.randi_range(20, 32)
		p["potential"] = maxi(p["potential"] - 10, Ratings.overall(p))
		p["club"] = -1
		players[p["id"]] = p
		free_agents.append(p["id"])


func _tidy_free_agents() -> void:
	# Unsigned veterans retire; keep the pool between 30 and 50 players.
	for pid in free_agents.duplicate():
		if players[pid]["age"] >= 31 and rng.randf() < 0.6:
			free_agents.erase(pid)
			players.erase(pid)
	if free_agents.size() > 90:
		free_agents.sort_custom(func(a: int, b: int) -> bool: return Ratings.value(players[a]) > Ratings.value(players[b]))
		for pid in free_agents.slice(90):
			players.erase(pid)
		free_agents.resize(90)


func _make_youth(pos: String, base: float, names: Dictionary) -> Dictionary:
	var offsets := {
		"GK": {"reflexes": 8, "handling": 6, "crossing": -25, "shooting": -30, "dribbling": -25, "tackling": -25},
		"DEF": {"tackling": 8, "heading": 6, "strength": 5, "shooting": -15, "reflexes": -40, "handling": -40},
		"MID": {"passing": 8, "stamina": 5, "dribbling": 4, "reflexes": -40, "handling": -40},
		"FWD": {"shooting": 8, "pace": 5, "dribbling": 5, "tackling": -18, "reflexes": -40, "handling": -40},
	}
	var stats := {}
	for a in Ratings.ATTRS:
		stats[a] = clampi(int(round(base + offsets[pos].get(a, 0) + rng.randfn(0, 5))), 1, 99)
	var nations: Array = names.keys()
	var nation: String = nations[rng.randi() % nations.size()]
	var pool: Array = names[nation]
	var first: Array = pool[0]
	var last: Array = pool[1]
	var id := next_pid
	next_pid += 1
	var p := {
		"id": id, "name": "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]],
		"nation": nation, "age": rng.randi_range(16, 17), "pos": pos, "stats": stats,
		"potential": clampi(int(base + 14 + rng.randf_range(5, 30)), 30, 95),
		"look": {"skin": Kits.SKIN_TONES[rng.randi() % Kits.SKIN_TONES.size()].to_html(false),
			"hair": (SpriteData.HAIR_STYLES + [""])[rng.randi() % (SpriteData.HAIR_STYLES.size() + 1)],
			"hair_colour": Kits.HAIR_COLOURS[rng.randi() % Kits.HAIR_COLOURS.size()].to_html(false)},
		"club": -1, "condition": 100.0, "injury": 0, "s_apps": 0, "s_goals": 0, "apps": 0, "goals": 0,
	}
	return p


## First and last names already in the world, grouped by nation, for new players.
func _name_pool() -> Dictionary:
	var pool := {}
	for pid in players:
		var p: Dictionary = players[pid]
		var parts: PackedStringArray = str(p["name"]).split(" ", false, 1)
		if parts.size() < 2:
			continue
		var n: String = p.get("nation", "")
		if not pool.has(n):
			pool[n] = [[], []]
		if not pool[n][0].has(parts[0]):
			pool[n][0].append(parts[0])
		if not pool[n][1].has(parts[1]):
			pool[n][1].append(parts[1])
	return pool


func _trim_squad(cid: int) -> void:
	var c: Dictionary = clubs[cid]
	while c["players"].size() > 22:
		var worst := -1
		var wv := INF
		for pid in c["players"]:
			var v := float(Ratings.value(players[pid]))
			if v < wv:
				wv = v
				worst = pid
		_move_player(worst, -1, 0)


# ------------------------------------------------------------------ match hand-off

## Team description for the match scene.
func match_team(cid: int, use_away_kit: bool) -> Dictionary:
	var c: Dictionary = clubs[cid]
	validate_lineup(cid)
	var kit_src: Dictionary = c["away"] if use_away_kit else c["home"]
	var kit := {"shirt": Color(kit_src["shirt"]), "shorts": Color(kit_src["shorts"]), "socks": Color(kit_src["socks"]),
		"gk": Color(c["gk"]), "name": c["name"], "short": c["short"]}
	var roles := roles_for(cid)
	var list: Array = []
	for i in c["lineup"].size():
		var p: Dictionary = players[c["lineup"][i]]
		list.append({"id": p["id"], "name": p["name"], "role": roles[i], "stats": p["stats"],
			"energy": float(p["condition"]) / 100.0,
			"look": {"skin": Color(p["look"]["skin"]), "hair_style": p["look"]["hair"], "hair_colour": Color(p["look"]["hair_colour"])}})
	return {"club": cid, "name": c["name"], "short": c["short"], "kit": kit, "formation": c["formation"], "players": list}


static func kits_clash(a: Dictionary, b: Dictionary) -> bool:
	var ca := Color(a["shirt"])
	var cb := Color(b["shirt"])
	return absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) < 0.6


# ------------------------------------------------------------------ save / load

func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "year": year, "week": week, "calendar": calendar, "divisions": divisions, "division_names": division_names,
		"clubs": clubs, "players": players, "free_agents": free_agents, "fixtures": fixtures, "cup": cup,
		"history": history, "news": news, "user": user, "next_pid": next_pid, "season_summary": season_summary}


func from_dict(d: Dictionary) -> void:
	rng.randomize()
	year = d["year"]; week = d["week"]; calendar = d["calendar"]; divisions = d["divisions"]
	division_names = d["division_names"]; clubs = d["clubs"]; players = d["players"]
	free_agents = d["free_agents"]; fixtures = d["fixtures"]; cup = d["cup"]; history = d["history"]
	news = d["news"]; user = d["user"]; next_pid = d["next_pid"]; season_summary = d.get("season_summary", {})


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var(to_dict())


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## True if there's a save from an older, incompatible version (5-a-side careers).
static func old_save() -> bool:
	return has_save() and load_saved() == null


static func load_saved() -> Career:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var v: Variant = f.get_var()
	if not (v is Dictionary) or int((v as Dictionary).get("version", 1)) != SAVE_VERSION:
		return null
	var c := Career.new()
	c.from_dict(v)
	return c
