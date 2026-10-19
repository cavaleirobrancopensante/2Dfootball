class_name Kits
## Team kits and the random looks (skin tone, hair) given to each player.

const TEAMS := [
	{"name": "Red Rovers", "short": "RRO", "shirt": Color("#d02030"), "shorts": Color("#f4f4f4"), "socks": Color("#d02030"), "gk": Color("#2a2a2a")},
	{"name": "Blue Harbour", "short": "BLH", "shirt": Color("#2060d0"), "shorts": Color("#f4f4f4"), "socks": Color("#2060d0"), "gk": Color("#e8c020")},
	{"name": "Canary FC", "short": "CAN", "shirt": Color("#f2d020"), "shorts": Color("#1f50b0"), "socks": Color("#f4f4f4"), "gk": Color("#20a050")},
	{"name": "Emerald Town", "short": "EME", "shirt": Color("#18904a"), "shorts": Color("#f4f4f4"), "socks": Color("#18904a"), "gk": Color("#f08020")},
	{"name": "Black Knights", "short": "BKN", "shirt": Color("#262626"), "shorts": Color("#262626"), "socks": Color("#f4f4f4"), "gk": Color("#30c0e0")},
	{"name": "Orange Lions", "short": "ORL", "shirt": Color("#f07a18"), "shorts": Color("#262626"), "socks": Color("#f07a18"), "gk": Color("#a030c0")},
	{"name": "Sky City", "short": "SKY", "shirt": Color("#78c0f0"), "shorts": Color("#f4f4f4"), "socks": Color("#1a2a60"), "gk": Color("#d02030")},
	{"name": "Purple Hill", "short": "PUR", "shirt": Color("#7a30b0"), "shorts": Color("#f4f4f4"), "socks": Color("#7a30b0"), "gk": Color("#e8e030")},
]

const SKIN_TONES := [
	Color("#f5d3b8"), Color("#eabf9c"), Color("#d9a27a"), Color("#c08458"),
	Color("#9a6440"), Color("#7a4a2c"), Color("#5a3420"),
]

const HAIR_COLOURS := [
	Color("#1a1412"), Color("#2e1e14"), Color("#4a2e1a"), Color("#7a4e28"),
	Color("#c09048"), Color("#e2c27a"), Color("#a43a20"), Color("#8a8a8a"),
]


## Returns {skin, hair_style ("" = bald), hair_colour}.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var styles: Array = SpriteData.HAIR_STYLES.duplicate()
	styles.append("")   # some players are bald
	var style: String = styles[rng.randi() % styles.size()]
	return {
		"skin": SKIN_TONES[rng.randi() % SKIN_TONES.size()],
		"hair_style": style,
		"hair_colour": HAIR_COLOURS[rng.randi() % HAIR_COLOURS.size()],
	}


## Picks an opponent kit that won't clash with the player's.
static func contrasting(team: int, rng: RandomNumberGenerator) -> int:
	var mine: Color = TEAMS[team]["shirt"]
	var options: Array = []
	for i in TEAMS.size():
		if i == team:
			continue
		var c: Color = TEAMS[i]["shirt"]
		var diff := absf(c.r - mine.r) + absf(c.g - mine.g) + absf(c.b - mine.b)
		if diff > 0.7:
			options.append(i)
	return options[rng.randi() % options.size()]
