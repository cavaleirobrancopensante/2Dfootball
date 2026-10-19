# 2D Football

**Play in your browser: https://cavaleirobrancopensante.github.io/2Dfootball/**

Arcade 5-a-side football for mobile, made in Godot 4.7. Pick your team, then play a 3-minute match against the computer. There are no throw-ins: the ball bounces off the boards.

## Controls

| | With the ball | Without the ball |
| --- | --- | --- |
| **Left thumb** (anywhere on the left) | dribble | run |
| **Red button** | **SHOOT** — hold to power up, release to shoot (aim with the left thumb) | **TACKLE** — slide tackle |
| **Blue button** | **PASS** — to the teammate in the direction you're pushing | **SWITCH** — take control of the teammate nearest the ball |

The game switches you to the right player automatically (the one nearest the ball, or the one you passed to). Shots that are heading roughly at goal get nudged into the frame. Passes over ~650px go in the air.

Desktop: WASD/arrows, **K** (or Space) = red button, **J** = blue button. The mouse works like a finger.

## How the players are drawn

All players share one sprite sheet drawn in **key colours**: skin magenta, shirt red, shorts blue, socks yellow. `shaders/recolor.gdshader` swaps those for each player's real colours, so one set of sprites covers every team kit and skin tone. Hair is a separate overlay (green key colour), placed on the head in every frame, in 6 styles plus bald.

The sheets cover 5 directions (down, down-right, right, up-right, up); the left-facing ones are mirrored. Animations: idle, run, kick, pass, slide, header, fall, celebrate.

### Adding or replacing sprites

1. Put the new sheets in `assets/source/` (`players_body.png`, `players_hair.png`).
2. Run `python3 tools/extract_sprites.py assets/players` from the repo root (needs Python with Pillow, NumPy, SciPy).

This snaps every pixel to an exact key colour, slices the frames, lines them up at the feet, finds the head in every frame, and regenerates `scripts/sprite_data.gd`. If the new sheet's grid is laid out differently, adjust the `PX`/`RY` panel and row boundaries in the script.

## Project layout

| Path | What |
| --- | --- |
| `scripts/match.gd` | Rules, AI, kick-off/goal/full-time flow, camera, HUD, menu |
| `scripts/footballer.gd` | A player: movement, animation, recolouring, hair, actions |
| `scripts/ball.gd` | Ball physics with height, bounces off the boards, goal detection |
| `scripts/controls.gd` | Touch joystick and buttons |
| `scripts/kits.gd` | Team kits, skin tones, hair colours |
| `scripts/pitch.gd` | Draws the pitch, goals and stands |
| `scripts/sprite_data.gd` | Generated: frame counts, anchors, head positions |
| `tools/simulate.gd` | AI-vs-AI test: `godot --headless --fixed-fps 60 --script res://tools/simulate.gd` |

## Browser version

Every push to `main` runs `.github/workflows/web.yml`, which exports the game with Godot 4.7 and publishes it to GitHub Pages a couple of minutes later. The version (Project Settings → Application → Config → Version) shows in the bottom corner; see `CHANGELOG.md`.

One-time setup, if the first build's deploy step fails: in the repo's *Settings → Pages*, set **Source** to **GitHub Actions**.
