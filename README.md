# Coin Collector

A small 2D platformer built with Godot in which the player collects coins while avoiding traps. Every action is recorded to a [JSON Lines](https://jsonlines.org/) file following a documented schema, and a Python validator checks that the recorded data is consistent.

## Gameplay

- Move the blue square with **A/D** or the **left/right arrows**. Jump with **W**, **Space** or the **up arrow**.
- Collect all 7 coins. They sit at fixed places in a single fixed level.
- Gray blocks are solid: you can stand on them and cannot pass through them.
- Red spikes are traps, and falling into a gap in the ground is also fatal. Dying puts you back at the start of the level with every coin restored, and the round keeps going.
- There is no time limit. The round is complete when you have collected every coin in one attempt. Press **Enter** to play again.

## Event log

Events are appended to `user://events.jsonl` (on Windows: `%APPDATA%\Godot\app_userdata\Coin Collector\events.jsonl`), one JSON object per line:

```json
{"timestamp":"2026-10-31T02:28:52.895Z","evento":"player_death","valor":{"cause":"trap","t":0.208,"x":90.0,"y":528.0},"session_id":"ee975668-b7d3-4c8e-a82f-b5701c898b91","round_id":"f2e2d1fa-b0e6-4892-a5c6-9c80be8467fd","schema_version":2}
```

| Field | Description |
|---|---|
| `timestamp` | UTC time, ISO 8601 with milliseconds |
| `evento` | Event type (below) |
| `valor` | Object whose fields depend on `evento` |
| `session_id` | UUID of the game session (one program run) |
| `round_id` | UUID of the round, or `null` for session events |
| `schema_version` | `2` for the platformer (`1` was the earlier arena version) |

In `valor`, `t` is seconds since the round started, and `x`/`y` are level coordinates (800×600, y grows downward).

| `evento` | Fired when | `valor` |
|---|---|---|
| `session_start` | the game starts | `{}` |
| `round_start` | a round begins | `t` |
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

The formal definitions are [`schema/events.v2.schema.json`](schema/events.v2.schema.json) and [`schema/events.v1.schema.json`](schema/events.v1.schema.json) (JSON Schema 2020-12). Design decisions are recorded in [`docs/adr/`](docs/adr/), and domain terms in [`GLOSSARY.md`](GLOSSARY.md).

## Validating the data

```bash
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt   # Windows; use .venv/bin/pip elsewhere
.venv/Scripts/python validate_events.py [path/to/events.jsonl]
```

Without an argument it reads the default Windows log path. Each line is checked against the schema for its own `schema_version`, so logs from both versions validate. On top of the schema it verifies per round that:

- the round starts once, ends once, and event times never go backwards;
- the `round_end` counters match the recorded `coin_collect`, `player_position`, `player_jump` and `player_death` events;
- every death is followed by a respawn, and every attempt spawns each coin exactly once;
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
| `main.gd` | Level data, physics, game rules and drawing with native shapes; `_step()` is input-free so it can be simulated |
| `event_logger.gd` | `EventLogger`: adds ids, timestamp and schema version, appends one JSON line |
| `schema/` | JSON Schema for one log line, per `schema_version` |
| `validate_events.py` | Schema and consistency validator |
| `GLOSSARY.md`, `docs/adr/` | Domain language and design decisions |

## Built with

- [Godot Engine](https://godotengine.org/) 4.7 (GDScript, GL Compatibility renderer)
- Python 3 with [jsonschema](https://python-jsonschema.readthedocs.io/)
- [Claude Code](https://claude.com/claude-code)
