class_name Ratings
## Player maths shared by the career and the match: overall ratings,
## market value, wages, and team strength for simulated matches.

const ATTRS := ["pace", "acceleration", "stamina", "passing", "crossing", "shooting", "power",
	"dribbling", "tackling", "heading", "strength", "reflexes", "handling"]

const LABELS := {
	"pace": "Pace", "acceleration": "Acceleration", "stamina": "Stamina", "passing": "Passing",
	"crossing": "Crossing", "shooting": "Shooting", "power": "Shot power", "dribbling": "Dribbling",
	"tackling": "Tackling", "heading": "Heading", "strength": "Strength", "reflexes": "Reflexes (GK)",
	"handling": "Handling (GK)",
}

const ROLE_WEIGHTS := {
	"GK": {"reflexes": 0.45, "handling": 0.35, "strength": 0.1, "acceleration": 0.1},
	"DEF": {"tackling": 0.3, "strength": 0.15, "heading": 0.15, "pace": 0.1, "acceleration": 0.05,
		"passing": 0.1, "stamina": 0.1, "dribbling": 0.05},
	"MID": {"passing": 0.25, "dribbling": 0.15, "stamina": 0.15, "tackling": 0.1, "shooting": 0.1,
		"crossing": 0.1, "acceleration": 0.1, "pace": 0.05},
	"FWD": {"shooting": 0.3, "power": 0.1, "dribbling": 0.15, "pace": 0.15, "acceleration": 0.1,
		"heading": 0.1, "passing": 0.05, "crossing": 0.05},
}

## Formations: each outfield slot is [role, x, y] as fractions of the pitch for a
## team attacking to the right (x = 0 own goal line). The keeper is always added first.
const FORMATIONS := {
	"4-4-2": [["DEF", 0.15, 0.16], ["DEF", 0.14, 0.38], ["DEF", 0.14, 0.62], ["DEF", 0.15, 0.84],
		["MID", 0.28, 0.16], ["MID", 0.27, 0.38], ["MID", 0.27, 0.62], ["MID", 0.28, 0.84],
		["FWD", 0.40, 0.40], ["FWD", 0.40, 0.60]],
	"4-3-3": [["DEF", 0.15, 0.16], ["DEF", 0.14, 0.38], ["DEF", 0.14, 0.62], ["DEF", 0.15, 0.84],
		["MID", 0.27, 0.30], ["MID", 0.25, 0.50], ["MID", 0.27, 0.70],
		["FWD", 0.38, 0.18], ["FWD", 0.40, 0.50], ["FWD", 0.38, 0.82]],
	"3-5-2": [["DEF", 0.14, 0.27], ["DEF", 0.13, 0.50], ["DEF", 0.14, 0.73],
		["MID", 0.29, 0.10], ["MID", 0.26, 0.32], ["MID", 0.24, 0.50], ["MID", 0.26, 0.68], ["MID", 0.29, 0.90],
		["FWD", 0.40, 0.40], ["FWD", 0.40, 0.60]],
	"4-5-1": [["DEF", 0.15, 0.16], ["DEF", 0.14, 0.38], ["DEF", 0.14, 0.62], ["DEF", 0.15, 0.84],
		["MID", 0.29, 0.12], ["MID", 0.27, 0.32], ["MID", 0.25, 0.50], ["MID", 0.27, 0.68], ["MID", 0.29, 0.88],
		["FWD", 0.40, 0.50]],
	"5-3-2": [["DEF", 0.16, 0.10], ["DEF", 0.14, 0.30], ["DEF", 0.13, 0.50], ["DEF", 0.14, 0.70], ["DEF", 0.16, 0.90],
		["MID", 0.27, 0.30], ["MID", 0.25, 0.50], ["MID", 0.27, 0.70],
		["FWD", 0.40, 0.40], ["FWD", 0.40, 0.60]],
}
const DEFAULT_FORMATION := "4-4-2"


## Outfield roles of a formation, in slot order.
static func roles(formation: String) -> Array:
	var list: Array = []
	for s in FORMATIONS.get(formation, FORMATIONS[DEFAULT_FORMATION]):
		list.append(s[0])
	return list


## Pitch fractions of every slot (keeper first) for a team attacking right.
static func spots(formation: String) -> Array:
	var list: Array = [Vector2(0.025, 0.5)]
	for s in FORMATIONS.get(formation, FORMATIONS[DEFAULT_FORMATION]):
		list.append(Vector2(s[1], s[2]))
	return list


static func stat(p: Dictionary, a: String) -> float:
	return float(p["stats"].get(a, 50))


static func overall(p: Dictionary, role := "") -> int:
	if role == "":
		role = p["pos"]
	var w: Dictionary = ROLE_WEIGHTS[role]
	var s := 0.0
	for a in w:
		s += stat(p, a) * float(w[a])
	return int(round(s))


static func value(p: Dictionary) -> int:
	var ovr := overall(p)
	var age: int = p["age"]
	var pot: int = p["potential"]
	var v := 20000.0 * exp(0.14 * (ovr - 40))
	var f := 1.0
	if age <= 21:
		f = 1.0 + maxf(pot - ovr, 0) * 0.05
	elif age <= 27:
		f = 1.0 + maxf(pot - ovr, 0) * 0.02
	elif age <= 30:
		f = 0.9
	elif age == 31:
		f = 0.7
	elif age == 32:
		f = 0.55
	else:
		f = 0.35
	return round_money(v * f)


static func wage(p: Dictionary) -> int:
	return round_money(maxf(300.0, value(p) * 0.003))


static func round_money(v: float) -> int:
	if v < 1000.0:
		return int(round(v / 10.0) * 10)
	var mag := pow(10.0, floor(log(v) / log(10.0)) - 1.0)
	return int(round(v / mag) * mag)


static func money(v: float) -> String:
	var neg := v < 0
	v = absf(v)
	var s := ""
	if v >= 1000000.0:
		s = "€%.1fM" % (v / 1000000.0)
	elif v >= 1000.0:
		s = "€%dk" % int(round(v / 1000.0))
	else:
		s = "€%d" % int(v)
	return ("-" if neg else "") + s


## Attack and defence strength of a lineup (for simulated matches).
## lineup: Array of player dictionaries, keeper first; roles: matching roles.
static func team_strength(lineup: Array, roles: Array) -> Vector2:
	var att := 0.0
	var defn := 0.0
	var wa := 0.0
	var wd := 0.0
	var gk := 40.0
	for i in lineup.size():
		var p: Dictionary = lineup[i]
		var role: String = roles[i]
		var cond := 0.72 + 0.28 * float(p.get("condition", 100.0)) / 100.0
		if role == "GK":
			gk = (stat(p, "reflexes") * 0.55 + stat(p, "handling") * 0.45) * cond
			continue
		var a := (stat(p, "shooting") * 0.3 + stat(p, "dribbling") * 0.2 + stat(p, "passing") * 0.2
			+ stat(p, "pace") * 0.15 + stat(p, "acceleration") * 0.1 + stat(p, "power") * 0.05) * cond
		var d := (stat(p, "tackling") * 0.4 + stat(p, "strength") * 0.2 + stat(p, "heading") * 0.15
			+ stat(p, "pace") * 0.15 + stat(p, "stamina") * 0.1) * cond
		var w_att: float = {"FWD": 1.0, "MID": 0.7, "DEF": 0.3}[role]
		var w_def: float = {"FWD": 0.3, "MID": 0.6, "DEF": 1.0}[role]
		att += a * w_att
		wa += w_att
		defn += d * w_def
		wd += w_def
	att = att / maxf(wa, 0.01)
	defn = (defn / maxf(wd, 0.01)) * 0.65 + gk * 0.35
	return Vector2(att, defn)
