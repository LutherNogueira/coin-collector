# Reference

Details moved out of the README to keep it short. Back to the [README](../README.md).

## Gameplay

- Move the blue square with **A/D** or the **left/right arrows**. Jump with **W**, **Space** or the **up arrow**.
- Collect every coin (the fruits) in the level. Grass-topped blocks are solid: you can stand on them and cannot pass through them.
- Spikes are traps (only the visible spike tips kill), and falling into a gap in the ground is also fatal. Dying plays a short "hit" animation, then after 0.6 seconds puts you back at the start of the level with every coin restored, and the round keeps going.
- There is no time limit. The round is complete when you have collected every coin in one attempt. Press **Enter** for a new level.
- **Touch screens** get on-screen controls drawn over the game: an analog stick that appears under your left thumb (push gently to walk, fully to run), the right half of the screen to jump, and a pause button in the top right corner that opens the same menu as **Esc**, where **Sound** mutes everything (like **M**). On a computer, add `?touch` to the address to try them with the mouse.
- The first round of a session plays the hand-made level (level 0). Every later round plays a randomly generated one; its seed is shown in the corner.
- **Esc** opens a menu and pauses the game (the round clock and the event log stop with it): resume, **choose your character** (Ninja Frog, Mask Dude, Pink Man or Virtual Guy, remembered between visits) and open the **statistics** screen. The choice is a personal setting and is not part of the telemetry.
- Everything is drawn with pixel art from the Pixel Adventure pack: the player faces the direction of movement and switches between idle, run, jump and fall animations (a short "hit" animation plays where you die), coins are animated fruits with a burst when collected, the terrain uses grass-topped tiles, and a tiled sky background drifts slowly behind. Background music loops during play, and jumping, collecting a fruit, dying and finishing a level each play a sound effect; **M** mutes everything. **F1** shows the real collision shapes (player box, spike hitboxes, coin circles), which are independent of the art.

## Level generation

`Level.generate(seed)` in [`level.gd`](../level.gd) builds a one-screen level from an integer seed, so the same seed always gives the same level. It places ground segments separated by pits, short chains of platforms, spikes, solid blocks and 6–9 coins, using rules that keep everything within jump range (about 100 px high and 170 px across). Every solid and trap sits on a 16 px grid so the tile art lines up.

Rules are not a guarantee, so [`tests/verify_levels.gd`](../tests/verify_levels.gd) checks the result: it runs structural checks (counts, no overlaps, 16 px grid) and then simulates the player — walking and jumping with direction changes mid-air, using the same physics as the game — to confirm every coin can be touched on a path where the player stays alive. The hand-made level and 634 generated ones (seeds 1–181 and three ranges of 151 seeds, including seeds that exposed bugs while the generator was being built) pass. That is a large sample, not a proof: an unverified seed could still produce an unfinishable level.

```bash
godot --headless --path . --script res://tests/verify_levels.gd -- --from=0 --seeds=60
godot --headless --path . --script res://tests/simulate_round.gd   # scripted play that writes a real log
```

## Event log

Events are appended to `user://events.jsonl` (on Windows: `%APPDATA%\Godot\app_userdata\Coin Collector\events.jsonl`), one JSON object per line:

```json
{"timestamp":"2026-11-02T03:30:09.621Z","evento":"round_start","valor":{"level_seed":1891284687,"t":0.0},"session_id":"f983eb31-7604-4041-b3dc-b8cfe6b5da70","round_id":"8fd44feb-ba38-4977-95d9-00590a7e0b2b","schema_version":4}
```

| Field | Description |
|---|---|
| `timestamp` | UTC time, ISO 8601 with milliseconds |
| `evento` | Event type (below) |
| `valor` | Object whose fields depend on `evento` |
| `session_id` | UUID of the game session (one program run) |
| `round_id` | UUID of the round, or `null` for session events |
| `schema_version` | `4` (`1` arena, `2` platformer with one fixed level, `3` generated levels) |

In `valor`, `t` is seconds since the round started, and `x`/`y` are level coordinates (800×600, y grows downward).

| `evento` | Fired when | `valor` |
|---|---|---|
| `session_start` | the game starts | `{}` |
| `round_start` | a round begins | `t`, `level_seed` (0 = hand-made level, otherwise the generator seed), `generator_version` |
| `coin_spawn` | a coin is placed, at round start and after every death | `t`, `coin_id`, `x`, `y` |
| `coin_collect` | the player takes a coin | `t`, `coin_id`, `x`, `y`, `dt` (seconds since it last spawned) |
| `player_position` | every 0.5 s during a round | `t`, `x`, `y` |
| `player_jump` | the player jumps | `t`, `x`, `y` |
| `player_land` | the player lands after being airborne | `t`, `x`, `y`, `vy` (impact speed, px/s) |
| `player_death` | a trap is touched or the player falls into a pit | `t`, `x`, `y`, `cause` (`trap` or `pit`) |
| `player_respawn` | at the start point, 0.6 s after a death | `t`, `x`, `y` |
| `round_end` | the round finishes or the window is closed | `t`, `completed`, `coins_collected`, `coins_total`, `deaths`, `jumps`, `position_samples`, `duration_s` |
| `session_end` | the window is closed | `{}` |

`round_end.coins_collected` counts every `coin_collect` in the round, across attempts. `completed` is `false` when the window was closed before all coins were collected.

The formal definitions are in [`schema/`](../schema/), one JSON Schema 2020-12 file per `schema_version`. A level is determined by its seed *and* the version of the level code, so `level_seed` plus `generator_version` is what lets an analysis reconstruct the layout a round was played on. The version goes up whenever the hand-made level or the generator changes (schema 3 logs correspond to version 1). Design decisions are recorded in [`docs/adr/`](adr/), and domain terms in [`GLOSSARY.md`](../GLOSSARY.md).

## Validating the data

```bash
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt   # Windows; use .venv/bin/pip elsewhere
.venv/Scripts/python validate_events.py [path/to/events.jsonl]
```

Without an argument it reads the default Windows log path. Each line is checked against the schema for its own `schema_version`, so logs from both versions validate. On top of the schema it verifies per round that:

- the round starts once, ends once, and event times never go backwards;
- the `round_end` counters match the recorded `coin_collect`, `player_position`, `player_jump` and `player_death` events;
- every death is followed by a respawn, and nothing but `coin_spawn` is recorded while the player is dead;
- every attempt spawns each coin exactly once, at the same place;
- a round marked `completed` collected all of its coins.

It exits with `0` when everything passes and `1` when there are problems.

## Telemetry pipeline (layers and metrics)

[`pipeline/`](../pipeline/) turns the event log into metrics with Python and [DuckDB](https://duckdb.org/), in three layers (a "medallion" architecture):

| Layer | Holds | Where |
|---|---|---|
| **Bronze** | every line exactly as received, with source file and line number, broken lines included | `bronze.raw_events` |
| **Silver** | clean, typed events with schema versions 2, 3 and 4 conformed to one shape, plus `quarantine`: each rejected line with one reason (`invalid_json`, `missing_field`, `invalid_timestamp`, `timestamp_out_of_range`, `unsupported_schema_version`, `unknown_event`, `value_out_of_range`, `duplicate`) | `silver.events`, `silver.rounds`, `silver.deaths`, `silver.quarantine` |
| **Gold** | the metrics | `gold.daily_metrics`, `gold.summary`, `gold.deaths_by_cause`, `gold.deadliest_levels`, `gold.data_quality` |

Metrics, per day in UTC: **rounds**, **completion rate** (completed rounds over rounds that ended), **average and median duration** of completed rounds, and **death rate** (deaths over attempts, where an attempt is one start of the level: the first of each round plus one per respawn).

```bash
pip install -r pipeline/requirements.txt
python -m pipeline.generate_synthetic --out pipeline/data/raw/synthetic --days 40      # synthetic demo data, with dirty rows
python -m pipeline.run_pipeline --raw pipeline/data/raw/synthetic --out pipeline/data/gold.json
python -m pipeline.run_pipeline --raw "$APPDATA/Godot/app_userdata/Coin Collector/events.jsonl" --label "real plays"
python -m unittest discover -s pipeline/tests -t .                                      # checks everything against ground truth
```

The synthetic generator is **not real players**: it writes days of plausible events and adds dirty rows on top, along with a `manifest.json` of the true answers, which the tests compare the pipeline against. See [ADR 0005](adr/0005-medallion-pipeline-tested-against-synthetic-truth.md).

## Running the web build locally

Install the web templates, then export and serve:

```bash
python tools/fetch_web_templates.py --version 4.7.2 --dest "$APPDATA/Godot/export_templates/4.7.2.stable"   # Windows path
godot --headless --path . --export-release "Web" build/web/index.html
python tools/serve_web.py          # http://127.0.0.1:8060/index.html
```

On the web, `user://events.jsonl` lives in the browser's own storage; what reaches the collection endpoint is sent separately (see the README). Browsers also only allow sound after the first key press or click.

## File reference

<details>
<summary>Every source file and what it does</summary>

| File | Purpose |
|---|---|
| `project.godot`, `main.tscn` | Project settings and main scene (a single `Node2D` with a script) |
| `main.gd` | Game rules, event logging and drawing with native shapes; `_step()` is input-free so it can be simulated |
| `player_view.gd` | `PlayerView`: sprite animations and mirroring for the chosen character, driven by the physics body; purely visual |
| `pause_menu.gd`, `avatars.gd`, `settings.gd` | The Esc menu, the list of playable characters, and the saved choice (`user://settings.cfg`) |
| `assets/` | Art, sounds and their credits ([`assets/CREDITS.md`](../assets/CREDITS.md)) |
| `tools/generate_sfx.py` | Synthesizes the sound effects into `assets/sounds/` (no third-party audio) |
| `tools/fetch_web_templates.py`, `tools/serve_web.py` | Install the web export templates; serve the web build locally |
| `export_presets.cfg`, `vercel.json`, `.github/workflows/` | Web export preset, Vercel configuration and the deploy workflow |
| `level.gd` | `Level`: the hand-made level and the seeded generator |
| `scrolling_background.gd` | `ScrollingBackground`: the drifting tiled sky; purely visual |
| `sfx.gd` | `Sfx`: plays the sound effects and handles mute |
| `music.gd` | `Music`: loops the background track |
| `level_view.gd` | `LevelView`: terrain tiles, spikes and animated fruit coins; purely visual |
| `platform_physics.gd` | `PlatformPhysics`: gravity, jumping and collisions as pure functions, shared by the game and the tests |
| `event_logger.gd` | `EventLogger`: adds ids, timestamp and schema version, appends one JSON line |
| `event_sender.gd` | `EventSender`: batches the event lines in the page and sends them with `sendBeacon` (web build only) |
| `touch_controls.gd` | `TouchControls`: floating analog stick, jump zone and menu button for touch screens |
| `ingest/` | The collection endpoint (`api/ingest.js`, validation, rate limit) and its Node tests |
| `pipeline/fetch_blobs.py` | Downloads the collected batches from Vercel Blob into a bronze source folder |
| `schema/` | JSON Schema for one log line, per `schema_version` |
| `validate_events.py` | Schema and consistency validator |
| `pipeline/` | The bronze/silver/gold telemetry pipeline, its synthetic data generator and tests |
| `stats/` | The statistics screen shown from the Esc menu, and its charts; reads the pipeline's gold JSON |
| `tests/` | Headless level verifier and scripted-play simulation |
| `GLOSSARY.md`, `docs/adr/` | Domain language and design decisions |

</details>
