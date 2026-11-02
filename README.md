# Coin Collector

A small 2D platformer built with Godot in which the player collects coins while avoiding traps. Every action is recorded to a [JSON Lines](https://jsonlines.org/) file following a documented schema, and a Python validator checks that the recorded data is consistent.

## Gameplay

- Move the blue square with **A/D** or the **left/right arrows**. Jump with **W**, **Space** or the **up arrow**.
- Collect every coin in the level. Gray blocks are solid: you can stand on them and cannot pass through them.
- Red spikes are traps, and falling into a gap in the ground is also fatal. Dying puts you back at the start of the level with every coin restored, and the round keeps going.
- There is no time limit. The round is complete when you have collected every coin in one attempt. Press **Enter** for a new level.
- The first round of a session plays the hand-made level (level 0). Every later round plays a randomly generated one; its seed is shown in the corner.

## Level generation

`Level.generate(seed)` in [`level.gd`](level.gd) builds a one-screen level from an integer seed, so the same seed always gives the same level. It places ground segments separated by pits, short chains of platforms, spikes, solid blocks and 6–9 coins, using rules that keep everything within jump range (about 100 px high and 170 px across).

Rules are not a guarantee, so [`tests/verify_levels.gd`](tests/verify_levels.gd) checks the result: it runs structural checks (counts, no overlaps) and then simulates the player — walking and jumping with direction changes mid-air, using the same physics as the game — to confirm every coin can be touched on a path where the player stays alive. The hand-made level and 483 generated ones (seeds 1–60 and three ranges of 141 seeds, including seeds that exposed bugs while the generator was being built) pass. That is a large sample, not a proof: an unverified seed could still produce an unfinishable level.

```bash
godot --headless --path . --script res://tests/verify_levels.gd -- --from=0 --seeds=60
godot --headless --path . --script res://tests/simulate_round.gd   # scripted play that writes a real log
```

## Event log

Events are appended to `user://events.jsonl` (on Windows: `%APPDATA%\Godot\app_userdata\Coin Collector\events.jsonl`), one JSON object per line:

```json
{"timestamp":"2026-11-02T03:30:09.621Z","evento":"round_start","valor":{"level_seed":1891284687,"t":0.0},"session_id":"f983eb31-7604-4041-b3dc-b8cfe6b5da70","round_id":"8fd44feb-ba38-4977-95d9-00590a7e0b2b","schema_version":3}
```

| Field | Description |
|---|---|
| `timestamp` | UTC time, ISO 8601 with milliseconds |
| `evento` | Event type (below) |
| `valor` | Object whose fields depend on `evento` |
| `session_id` | UUID of the game session (one program run) |
| `round_id` | UUID of the round, or `null` for session events |
| `schema_version` | `3` (`1` was the arena version, `2` the platformer with one fixed level) |

In `valor`, `t` is seconds since the round started, and `x`/`y` are level coordinates (800×600, y grows downward).

| `evento` | Fired when | `valor` |
|---|---|---|
| `session_start` | the game starts | `{}` |
| `round_start` | a round begins | `t`, `level_seed` (0 = hand-made level, otherwise the generator seed) |
| `coin_spawn` | a coin is placed, at round start and after every death | `t`, `coin_id`, `x`, `y` |
| `coin_collect` | the player takes a coin | `t`, `coin_id`, `x`, `y`, `dt` (seconds since it last spawned) |
| `player_position` | every 0.5 s during a round | `t`, `x`, `y` |
| `player_jump` | the player jumps | `t`, `x`, `y` |
| `player_land` | the player lands after being airborne | `t`, `x`, `y`, `vy` (impact speed, px/s) |
| `player_death` | a trap is touched or the player falls into a pit | `t`, `x`, `y`, `cause` (`trap` or `pit`) |
| `player_respawn` | right after a death, at the start point | `t`, `x`, `y` |
| `round_end` | the round finishes or the window is closed | `t`, `completed`, `coins_collected`, `coins_total`, `deaths`, `jumps`, `position_samples`, `duration_s` |
| `session_end` | the window is closed | `{}` |

`round_end.coins_collected` counts every `coin_collect` in the round, across attempts. `completed` is `false` when the window was closed before all coins were collected.

The formal definitions are in [`schema/`](schema/), one JSON Schema 2020-12 file per `schema_version`. Since a level is determined by its seed, `level_seed` is what lets an analysis reconstruct the layout a round was played on. Design decisions are recorded in [`docs/adr/`](docs/adr/), and domain terms in [`GLOSSARY.md`](GLOSSARY.md).

## Validating the data

```bash
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt   # Windows; use .venv/bin/pip elsewhere
.venv/Scripts/python validate_events.py [path/to/events.jsonl]
```

Without an argument it reads the default Windows log path. Each line is checked against the schema for its own `schema_version`, so logs from both versions validate. On top of the schema it verifies per round that:

- the round starts once, ends once, and event times never go backwards;
- the `round_end` counters match the recorded `coin_collect`, `player_position`, `player_jump` and `player_death` events;
- every death is followed by a respawn, and every attempt spawns each coin exactly once, at the same place;
- a round marked `completed` collected all of its coins.

It exits with `0` when everything passes and `1` when there are problems.

## Running the game

1. Install [Godot 4.7](https://godotengine.org/) (tested with 4.7.2).
2. In the project manager, click **Import** and select `project.godot`.
3. Press F5.

## Project structure

| File | Purpose |
|---|---|
| `project.godot`, `main.tscn` | Project settings and main scene (a single `Node2D` with a script) |
| `main.gd` | Game rules, event logging and drawing with native shapes; `_step()` is input-free so it can be simulated |
| `level.gd` | `Level`: the hand-made level and the seeded generator |
| `platform_physics.gd` | `PlatformPhysics`: gravity, jumping and collisions as pure functions, shared by the game and the tests |
| `event_logger.gd` | `EventLogger`: adds ids, timestamp and schema version, appends one JSON line |
| `schema/` | JSON Schema for one log line, per `schema_version` |
| `validate_events.py` | Schema and consistency validator |
| `tests/` | Headless level verifier and scripted-play simulation |
| `GLOSSARY.md`, `docs/adr/` | Domain language and design decisions |

## Built with

- [Godot Engine](https://godotengine.org/) 4.7 (GDScript, GL Compatibility renderer)
- Python 3 with [jsonschema](https://python-jsonschema.readthedocs.io/)
- [Claude Code](https://claude.com/claude-code)
