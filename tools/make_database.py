"""Generate data/database.json: four divisions of fictional clubs and their players.

Everything in the JSON is meant to be edited by hand: rename clubs, players and
leagues, change ratings, ages, kits. The game reads it when a new career starts.

Usage (from the repo root): python3 tools/make_database.py [seed]
"""
import json
import random
import sys

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 2026
rng = random.Random(SEED)

ATTRS = ["pace", "acceleration", "stamina", "passing", "crossing", "shooting", "power",
         "dribbling", "tackling", "heading", "strength", "reflexes", "handling"]

LEAGUES = ["First Division", "Second Division", "Third Division", "Fourth Division"]
CLUBS_PER_LEAGUE = 10
SQUAD = ["GK", "GK", "GK"] + ["DEF"] * 7 + ["MID"] * 6 + ["FWD"] * 4   # 20 players
TIER_MEAN = [74, 64, 55, 46]    # average rating of a squad per division

TOWNS = [
    "Valdmoor", "Brenhaven", "Castellora", "Sankt Ruel", "Mirefield", "Porto Sereno", "Kalvik",
    "Ashcombe", "Dunmarra", "Lys Varenne", "Orvanto", "Thornwick", "Bellacqua", "Greyhollow",
    "Novaresk", "Santa Lumen", "Hollin Bay", "Marisport", "Eldenbrook", "Vila Aurora", "Kestrelmoor",
    "Ravensby", "Corvalho", "Ostrava Nova", "Fennick", "Quintara", "Solmere", "Brackenford",
    "Tavira Alta", "Wyndhurst", "Montclar", "Redwater", "Saltmarsh", "Isola Verde", "Harrowgate",
    "Cerro Blanco", "Lindqvist", "Port Ardent", "Embervale", "Rocabruna", "Velmont", "Glenarrow",
]
PATTERNS = ["{t} FC", "{t} United", "Athletic {t}", "{t} City", "{t} Rovers", "Sporting {t}",
            "{t} Wanderers", "Real {t}", "{t} Town", "Club {t}", "Inter {t}", "{t} Albion"]

COLOURS = {
    "red": "#d02030", "maroon": "#7a1a2a", "blue": "#2060d0", "navy": "#1a2a60", "sky": "#78c0f0",
    "yellow": "#f2d020", "orange": "#f07a18", "green": "#18904a", "lime": "#8cc63f",
    "white": "#f4f4f4", "black": "#262626", "purple": "#7a30b0", "claret": "#8a2040",
    "teal": "#1a9a9a", "grey": "#9a9a9a", "gold": "#c8a030",
}
GK_COLOURS = ["#e8c020", "#30c0e0", "#20a050", "#f08020", "#a030c0", "#e8e030", "#2a2a2a", "#e04090"]

NAMES = {
    "BRA": (["Lucas", "Mateus", "Gabriel", "Rafael", "Thiago", "Bruno", "Felipe", "Diego", "Caio", "Vinicius", "Rodrigo", "Gustavo", "Leandro", "Davi", "Igor"],
            ["Silva", "Santos", "Oliveira", "Souza", "Pereira", "Costa", "Ferreira", "Rodrigues", "Almeida", "Carvalho", "Ribeiro", "Barbosa", "Moreira", "Teixeira", "Araujo"]),
    "ENG": (["Jack", "Harry", "George", "Oliver", "Charlie", "Jacob", "Alfie", "Tom", "Callum", "Ryan", "Ben", "Josh", "Liam", "Sam", "Connor"],
            ["Smith", "Walker", "Hughes", "Turner", "Baker", "Collins", "Ward", "Barnes", "Fletcher", "Wood", "Mason", "Price", "Bennett", "Holt", "Reid"]),
    "IRL": (["Sean", "Cian", "Darragh", "Oisin", "Conor", "Eoin", "Niall", "Ronan", "Shane", "Fionn", "Padraig", "Cathal", "Kieran"],
            ["Murphy", "Kelly", "Byrne", "Ryan", "Walsh", "O'Brien", "Doyle", "McCarthy", "Gallagher", "Doherty", "Kennedy", "Lynch", "Nolan"]),
    "ESP": (["Pablo", "Alejandro", "Sergio", "Javier", "Adrian", "Raul", "Alvaro", "Iker", "Marcos", "Hugo", "Unai", "Jorge"],
            ["Garcia", "Martinez", "Lopez", "Sanchez", "Romero", "Navarro", "Torres", "Dominguez", "Gil", "Ortega", "Delgado", "Castro"]),
    "ITA": (["Luca", "Marco", "Matteo", "Andrea", "Federico", "Lorenzo", "Simone", "Davide", "Riccardo", "Stefano", "Giacomo"],
            ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo"]),
    "FRA": (["Hugo", "Theo", "Enzo", "Mathis", "Louis", "Nathan", "Antoine", "Clement", "Maxime", "Bastien", "Yanis", "Kylian"],
            ["Martin", "Bernard", "Dubois", "Moreau", "Laurent", "Lefebvre", "Girard", "Fournier", "Mercier", "Blanc", "Chevalier", "Roux"]),
    "GER": (["Lukas", "Jonas", "Felix", "Leon", "Niklas", "Tim", "Paul", "Moritz", "Jannik", "Florian", "Kai", "Stefan"],
            ["Muller", "Schmidt", "Schneider", "Fischer", "Weber", "Wagner", "Becker", "Hoffmann", "Koch", "Richter", "Klein", "Wolf"]),
    "POR": (["Joao", "Tiago", "Diogo", "Rui", "Andre", "Goncalo", "Nuno", "Pedro", "Ricardo", "Francisco", "Miguel"],
            ["Fernandes", "Goncalves", "Martins", "Lopes", "Marques", "Sousa", "Pinto", "Cardoso", "Mendes", "Nunes", "Vieira"]),
    "ARG": (["Facundo", "Santiago", "Nicolas", "Agustin", "Joaquin", "Matias", "Lautaro", "Franco", "Emiliano", "Gonzalo"],
            ["Gonzalez", "Fernandez", "Gomez", "Diaz", "Alvarez", "Acosta", "Benitez", "Medina", "Herrera", "Suarez", "Molina"]),
    "NGA": (["Chinedu", "Emeka", "Tunde", "Ikechukwu", "Samuel", "Victor", "Kelechi", "Femi", "Ahmed", "Daniel"],
            ["Okafor", "Adeyemi", "Eze", "Nwosu", "Balogun", "Okonkwo", "Bello", "Ogunleye", "Uche", "Abiola"]),
    "SEN": (["Moussa", "Cheikh", "Ibrahima", "Mamadou", "Abdou", "Pape", "Ousmane", "Lamine"],
            ["Diop", "Ndiaye", "Sarr", "Fall", "Diallo", "Cisse", "Faye", "Gueye", "Mbaye", "Sow"]),
    "JPN": (["Haruto", "Ren", "Sota", "Yuki", "Kaito", "Daiki", "Takumi", "Riku"],
            ["Sato", "Suzuki", "Takahashi", "Tanaka", "Watanabe", "Ito", "Nakamura", "Kobayashi", "Kato"]),
    "NED": (["Daan", "Sem", "Milan", "Jesse", "Thijs", "Bram", "Stijn", "Ruben"],
            ["de Jong", "Jansen", "de Vries", "van Dijk", "Bakker", "Visser", "Smit", "Meijer", "de Boer"]),
    "CRO": (["Luka", "Ivan", "Marko", "Josip", "Ante", "Mateo", "Domagoj"],
            ["Horvat", "Kovacic", "Babic", "Maric", "Juric", "Novak", "Vukovic", "Knezevic"]),
}
NATION_WEIGHT = {"BRA": 14, "ENG": 12, "IRL": 8, "ESP": 9, "ITA": 8, "FRA": 9, "GER": 8, "POR": 7,
                 "ARG": 7, "NGA": 6, "SEN": 5, "JPN": 4, "NED": 5, "CRO": 4}

SKIN = ["#f5d3b8", "#eabf9c", "#d9a27a", "#c08458", "#9a6440", "#7a4a2c", "#5a3420"]
SKIN_BY_NATION = {  # rough tendencies, plenty of overlap; skin is just a look
    "NGA": [4, 5, 6, 6], "SEN": [5, 6, 6, 4], "JPN": [0, 1, 1, 2], "BRA": [0, 1, 2, 3, 4, 5, 6],
    "ARG": [0, 1, 2, 2, 3], "POR": [1, 2, 2, 3, 4], "ESP": [1, 2, 2, 3], "ITA": [1, 2, 2, 3],
    "FRA": [0, 1, 2, 3, 4, 5, 6], "ENG": [0, 0, 1, 2, 4, 5], "IRL": [0, 0, 1, 1], "GER": [0, 0, 1, 2],
    "NED": [0, 0, 1, 2, 5], "CRO": [0, 1, 1, 2],
}
HAIR_STYLES = ["short", "long", "afro", "curly", "buzz", "ponytail", "fringe", "long2", "afro2", "curls", "crop", "buns", ""]
HAIR_COLOURS = ["#1a1412", "#2e1e14", "#4a2e1a", "#7a4e28", "#c09048", "#e2c27a", "#a43a20", "#8a8a8a"]

PROFILE = {   # offset from the player's base rating per attribute
    "GK": {"pace": -20, "acceleration": -12, "stamina": -15, "passing": -15, "crossing": -30, "shooting": -35,
           "power": -15, "dribbling": -30, "tackling": -30, "heading": -20, "strength": 0, "reflexes": 6, "handling": 4},
    "DEF": {"pace": -3, "acceleration": -5, "stamina": 2, "passing": -6, "crossing": -10, "shooting": -18,
            "power": -6, "dribbling": -10, "tackling": 8, "heading": 6, "strength": 6, "reflexes": -40, "handling": -40},
    "MID": {"pace": 0, "acceleration": 2, "stamina": 6, "passing": 7, "crossing": 2, "shooting": -3,
            "power": -2, "dribbling": 4, "tackling": -2, "heading": -6, "strength": -3, "reflexes": -40, "handling": -40},
    "FWD": {"pace": 5, "acceleration": 5, "stamina": -2, "passing": -3, "crossing": -4, "shooting": 8,
            "power": 4, "dribbling": 5, "tackling": -20, "heading": 0, "strength": 0, "reflexes": -40, "handling": -40},
}


def clamp(v, lo=1, hi=99):
    return max(lo, min(hi, int(round(v))))


def make_name(nation, used):
    firsts, lasts = NAMES[nation]
    for _ in range(50):
        n = f"{rng.choice(firsts)} {rng.choice(lasts)}"
        if n not in used:
            used.add(n)
            return n
    return f"{rng.choice(firsts)} {rng.choice(lasts)} Jr"


def make_player(pid, pos, base, used, age=None):
    nation = rng.choices(list(NATION_WEIGHT), weights=list(NATION_WEIGHT.values()))[0]
    if age is None:
        age = rng.choices(range(17, 36), weights=[2, 4, 6, 8, 9, 10, 10, 10, 9, 9, 8, 7, 6, 5, 4, 3, 2, 1, 1])[0]
    # Young players are a little below their level, veterans keep skill but lose legs.
    age_adj = -6 if age <= 19 else (-3 if age <= 21 else (0 if age <= 30 else -1))
    stats = {}
    for a in ATTRS:
        v = base + age_adj + PROFILE[pos][a] + rng.gauss(0, 5)
        if a in ("pace", "acceleration", "stamina") and age > 29:
            v -= (age - 29) * 1.8
        stats[a] = clamp(v)
    growth = max(0, 27 - age) * rng.uniform(0.8, 2.4)
    potential = clamp(base + age_adj + growth + rng.gauss(2, 4), base, 99)
    return {
        "id": pid, "name": make_name(nation, used), "nation": nation, "age": age, "pos": pos,
        "stats": stats, "potential": potential,
        "look": {"skin": SKIN[rng.choice(SKIN_BY_NATION[nation])],
                 "hair": rng.choice(HAIR_STYLES), "hair_colour": rng.choice(HAIR_COLOURS)},
    }


def make_kit():
    names = list(COLOURS)
    shirt = rng.choice(names)
    others = [c for c in names if c != shirt]
    shorts = rng.choice(["white", "black", shirt, rng.choice(others)])
    socks = rng.choice([shirt, shorts, "white"])
    return {"shirt": COLOURS[shirt], "shorts": COLOURS[shorts], "socks": COLOURS[socks]}, shirt


def main():
    used_names = set()
    towns = TOWNS[:]
    rng.shuffle(towns)
    clubs, players, leagues = [], [], []
    pid = 0
    shorts_used = set()
    for li, lname in enumerate(LEAGUES):
        ids = []
        for ci in range(CLUBS_PER_LEAGUE):
            cid = len(clubs)
            town = towns.pop()
            name = rng.choice(PATTERNS).format(t=town)
            short = "".join(ch for ch in town.upper() if ch.isalpha())[:3]
            while short in shorts_used:
                short = short[:2] + chr(rng.randint(65, 90))
            shorts_used.add(short)
            home, shirt_name = make_kit()
            away_choice = rng.choice([c for c in COLOURS if c != shirt_name and c != "grey"])
            away = {"shirt": COLOURS[away_choice], "shorts": rng.choice([COLOURS["white"], COLOURS["black"], COLOURS[away_choice]]),
                    "socks": COLOURS[away_choice]}
            strength = TIER_MEAN[li] + rng.uniform(-4, 4) + (CLUBS_PER_LEAGUE / 2 - ci) * 0.6
            reputation = clamp(strength + 10, 10, 99)
            squad = []
            for pos in SQUAD:
                players.append(make_player(pid, pos, strength + rng.gauss(0, 3), used_names))
                squad.append(pid)
                pid += 1
            clubs.append({
                "id": cid, "name": name, "short": short, "reputation": reputation,
                "budget": int(round(150000 * (2.6 ** (3 - li)) * rng.uniform(0.7, 1.4), -4)),
                "stadium": int(round(3000 * (2.2 ** (3 - li)) * rng.uniform(0.7, 1.5), -2)),
                "home": home, "away": away, "gk": rng.choice(GK_COLOURS), "players": squad,
            })
            ids.append(cid)
        leagues.append({"name": lname, "clubs": ids})
    free = []
    for _ in range(80):
        pos = rng.choice(["GK", "DEF", "DEF", "MID", "MID", "FWD", "FWD"])
        players.append(make_player(pid, pos, rng.uniform(40, 62), used_names))
        free.append(pid)
        pid += 1
    db = {
        "about": "Fictional football world for 2D Football. Edit freely: names, ages, ratings (1-99), kits (hex colours). Hair styles: " + ", ".join(h or '"" (bald)' for h in HAIR_STYLES) + ".",
        "version": 1, "start_year": 2026, "attributes": ATTRS,
        "leagues": leagues, "clubs": clubs, "players": players, "free_agents": free,
    }
    with open("data/database.json", "w") as f:
        json.dump(db, f, indent=1, ensure_ascii=False)
    print(len(clubs), "clubs,", len(players), "players")


if __name__ == "__main__":
    main()
