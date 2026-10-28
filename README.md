# Coin Collector

A small 2D game built with Godot in which the player collects coins while dodging obstacles. Every action is recorded to a [JSON Lines](https://jsonlines.org/) file following a documented schema, and a Python validator checks that the recorded data is consistent.

## Gameplay

- Move the blue square with **WASD** or the **arrow keys**.
- Collect the yellow coin; a new one appears at a random position each time. One coin is on screen at a time.
- Red obstacles cross the arena in straight lines (a new one every 2 seconds). Touching one kills you — you have one life.
- A round lasts 30 seconds and ends on death or when time runs out. Press **Enter** to play again.

## Event log

Events are appended to `user://events.jsonl` (on Windows: `%APPDATA%\Godot\app_userdata\Coin Collector\events.jsonl`), one JSON object per line:

```json
{"timestamp":"2026-10-28T19:32:17.611Z","evento":"coin_spawn","valor":{"t":0.0,"x":427.2,"y":259.4},"session_id":"c3b168bd-9f69-42a4-803e-41bf7f801b86","round_id":"1ddcca79-8140-4658-ba2b-5755f4fb2299","schema_version":1}
```

| Field | Description |
|---|---|
| `timestamp` | UTC time, ISO 8601 with milliseconds |
| `evento` | Event type (below) |
| `valor` | Object whose fields depend on `evento` |
| `session_id` | UUID of the game session (one program run) |
| `round_id` | UUID of the round, or `null` for session events |
| `schema_version` | Currently `1` |

In `valor`, `t` is seconds since the round started; `x` and `y` are arena coordinates (0–800, 0–600).

| `evento` | Fired when | `valor` |
|---|---|---|
| `session_start` | the game starts | `{}` |
| `round_start` | a round begins | `t` |
| `coin_spawn` | a coin appears | `t`, `x`, `y` |
| `coin_collect` | the player takes a coin | `t`, `x`, `y`, `dt` (seconds since that coin spawned) |
| `player_position` | every 0.5 s during a round | `t`, `x`, `y` |
| `player_death` | an obstacle hits the player | `t`, `x`, `y` |
| `round_end` | the round finishes | `t`, `coins_collected`, `obstacles_spawned`, `position_samples`, `duration_s` |
| `session_end` | the window is closed | `{}` |

`round_end` has no reason field: a round ended by death contains a `player_death` event, otherwise it ended by timeout. Closing the window mid-round also writes a `round_end` (with `duration_s` below 30) before `session_end`.

The formal definition is [`schema/events.schema.json`](schema/events.schema.json) (JSON Schema 2020-12). The design decision behind the object-valued `valor` is recorded in [`docs/adr/0001-event-payload-is-an-object-per-event-type.md`](docs/adr/0001-event-payload-is-an-object-per-event-type.md), and domain terms are defined in [`GLOSSARY.md`](GLOSSARY.md).

## Validating the data

```bash
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt   # Windows; use .venv/bin/pip elsewhere
.venv/Scripts/python validate_events.py [path/to/events.jsonl]
```

Without an argument it reads the default Windows log path. Besides checking every line against the schema, it verifies per round that:

- the round starts once and ends at most once, with at most one death;
- the `round_end` counters match the number of `coin_collect` and `player_position` events;
- event times never go backwards.

It exits with `0` when everything passes and `1` when there are problems.

## Running the game

1. Install [Godot 4.7](https://godotengine.org/) (tested with 4.7.2).
2. In the project manager, click **Import** and select `project.godot`.
3. Press F5.

## Project structure

| File | Purpose |
|---|---|
| `project.godot`, `main.tscn` | Project settings and main scene (a single `Node2D` with a script) |
| `main.gd` | Game logic and drawing with native shapes; `_step()` is input-free so it can be simulated |
| `event_logger.gd` | `EventLogger`: adds ids, timestamp and schema version, appends one JSON line |
| `schema/events.schema.json` | JSON Schema for one log line |
| `validate_events.py` | Schema and consistency validator |
| `GLOSSARY.md`, `docs/adr/` | Domain language and design decisions |

## Built with

- [Godot Engine](https://godotengine.org/) 4.7 (GDScript, GL Compatibility renderer)
- Python 3 with [jsonschema](https://python-jsonschema.readthedocs.io/)
- [Claude Code](https://claude.com/claude-code)
