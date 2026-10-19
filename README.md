# 2D Football

**Play in your browser: https://cavaleirobrancopensante.github.io/2Dfootball/**

Arcade 11-a-side football with a manager career on top, made in Godot 4.7 for mobile and browser. Matches last five minutes (90 on the clock) on a full-size pitch, with a minimap at the bottom of the screen.

- **Career:** pick a club in one of four divisions and manage it season after season: 20-man squads, five formations (4-4-2, 4-3-3, 3-5-2, 4-5-1, 5-3-2), fitness, transfers, finances, promotion and relegation, and a cup. Play each match yourself or simulate it.
- **Quick match:** jump straight into a match with any of 8 kits.

All clubs, players and leagues are fictional. Everything lives in one editable file, `data/database.json`. Rename clubs, players and leagues, change ratings, ages and kits there, on your own copy, and new careers start from your edited world.

## Controls

| | With the ball | Without the ball |
| --- | --- | --- |
| **Left thumb** | dribble | run |
| **× PASS** | tap: short pass · hold: long ball (the bar sets the distance) | SWITCH to the teammate nearest the ball |
| **□ SHOOT** | hold to power up, release to shoot | — |
| **○ CROSS** | hold to power up, release: in the attacking third it drops into the box, elsewhere it's a lofted ball | — |
| **△ DRIBBLE / TACKLE** | when your team has the ball: hold = sprint, tap = skill move past a defender | slide tackle |

A power bar appears over your player while charging. Too little power on a cross falls short, too much sails long. A full-power shot can fly over the bar. Sprinting burns stamina quickly. The pause button (top left) lets you resume, or in a career, simulate the rest of the match.

Desktop: WASD/arrows, **J** = ×, **K** (or Space) = □, **L** = ○, **I** = △, Esc = pause.

## Players and ratings

Every player has 13 ratings from 1 to 100: pace, acceleration, stamina, passing, crossing, shooting, shot power, dribbling, tackling, heading, strength, and for keepers reflexes and handling. In matches they decide:

- **Pace / acceleration:** top speed and how fast you get there.
- **Stamina:** how quickly energy drains. Tired players slow down and get less accurate.
- **Passing / crossing / shooting:** how far off target the ball goes. **Shot power** sets shot speed.
- **Dribbling:** keeping the ball under pressure, skill moves, first touch on fast balls.
- **Tackling:** winning the ball, standing or sliding.
- **Heading / strength:** winning headers and shoulder-to-shoulder duels.
- **Reflexes / handling:** a keeper's reach, dives and whether he holds on or spills it.

**Age** matters: young players improve each summer (faster if they play), players in their thirties lose pace and stamina first, and veterans retire. Age also sets recovery: after a match a 20-year-old is nearly fresh a week later, a 33-year-old isn't. Fitness carries into the next match, so rotate.

Each player has a market value in euros and a weekly wage based on rating, age and potential.

## Career

- 4 divisions of 10 clubs; 18 league rounds per season; top 2 go up, bottom 2 go down.
- A cup for all 40 clubs (the lowest 16 start in a preliminary round), single matches, penalties if level.
- Money: gate receipts by stadium size and reputation, TV money by division, prize money, wages every week.
- Transfers: buy from any club (they ask more for their starters), sign free agents, sell (you get an offer), or release.
- Every summer: ageing and development, retirements, 2 youth players per club.
- Saves automatically after every week. (Careers from 1.1, which was 5-a-side, can't be continued.)

## How the players are drawn

All players share one sprite sheet drawn in **key colours**: skin magenta, shirt red, shorts blue, socks yellow. `shaders/recolor.gdshader` swaps those for each player's real colours. Hair is a separate overlay (green key colour) in 12 styles plus bald. Keepers have their own sheet (`players_gk.png`): ready stance, catch and hold, throw, kick from hands, and a dive that's rotated to whichever way he dives.

### Replacing or adding sprites

Put the sheets in `assets/source/` and run `python3 tools/extract_sprites.py assets/players` from the repo root (needs Pillow, NumPy, SciPy). It snaps every pixel to an exact key colour, slices the frames, lines them up at the feet, finds the head in every frame, and regenerates `scripts/sprite_data.gd`. The second hair sheet mixes facing directions within rows, so its views are picked by hand in `HAIR2` inside the script.

### Regenerating the fictional world

`python3 tools/make_database.py [seed]` writes a fresh `data/database.json`. This overwrites any edits you made.

## Project layout

| Path | What |
| --- | --- |
| `scripts/app.gd` | Main menu, career screens, hand-off to matches |
| `scripts/career/career.gd` | Seasons, fixtures, cup, simulation, fitness, development, money, transfers, save |
| `scripts/career/ratings.gd` | Overall ratings, values, wages, team strength |
| `scripts/ui/ui.gd` | UI helpers and theme |
| `scripts/match.gd` | The match: rules, ratings in play, AI, controls, HUD |
| `scripts/footballer.gd` | A player on the pitch: movement, stamina, animation, recolouring, hair |
| `scripts/ball.gd`, `scripts/pitch.gd`, `scripts/controls.gd`, `scripts/kits.gd` | Ball physics, pitch drawing, touch controls, quick-match kits |
| `data/database.json` | The editable world |
| `tools/simulate.gd` | AI-vs-AI test: `godot --headless --fixed-fps 60 --script res://tools/simulate.gd` |

## Browser version

Every push to `main` runs `.github/workflows/web.yml`, which exports the game with Godot 4.7 and publishes it to GitHub Pages a couple of minutes later. The version (Project Settings → Application → Config → Version) shows in-game; see `CHANGELOG.md`.

One-time setup, if the deploy step fails: in the repo's *Settings → Pages*, set **Source** to **GitHub Actions**.
