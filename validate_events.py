"""Validate an events.jsonl file against the schema matching each line's `schema_version`.

Besides the JSON Schema check on every line, it verifies per-round consistency
(see `check_round_v1` and `check_round_platformer`).

Usage: python validate_events.py [path/to/events.jsonl]
"""
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA_DIR = Path(__file__).parent / "schema"
DEFAULT_LOG = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "Coin Collector" / "events.jsonl"


def load_validators() -> dict[int, Draft202012Validator]:
    validators = {}
    for path in sorted(SCHEMA_DIR.glob("events.v*.schema.json")):
        version = int(path.name.split(".")[1][1:])
        validators[version] = Draft202012Validator(json.loads(path.read_text(encoding="utf-8")))
    return validators


def main() -> int:
    log_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_LOG
    if not log_path.is_file():
        print(f"File not found: {log_path}")
        return 2

    validators = load_validators()
    problems: list[str] = []
    rounds: dict[str, list[dict]] = defaultdict(list)
    sessions: dict[str, list[str]] = defaultdict(list)
    total = 0

    for number, raw in enumerate(log_path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        total += 1
        try:
            event = json.loads(raw)
        except json.JSONDecodeError as error:
            problems.append(f"line {number}: invalid JSON ({error.msg})")
            continue
        version = event.get("schema_version") if isinstance(event, dict) else None
        if version not in validators:
            problems.append(f"line {number}: unsupported schema_version {version!r} (known: {sorted(validators)})")
            continue
        errors = sorted(validators[version].iter_errors(event), key=lambda e: list(e.path))
        for error in errors:
            where = ".".join(str(p) for p in error.path) or "<root>"
            problems.append(f"line {number}: {where}: {error.message}")
        if errors:
            continue
        sessions[event["session_id"]].append(event["evento"])
        if event["round_id"] is not None:
            rounds[event["round_id"]].append(event)

    for session_id, names in sessions.items():
        if names[0] != "session_start":
            problems.append(f"session {session_id[:8]}: first event is {names[0]}, expected session_start")
        if names.count("session_end") > 1:
            problems.append(f"session {session_id[:8]}: more than one session_end")

    for round_id, events in rounds.items():
        label = round_id[:8]
        check = check_round_v1 if events[0]["schema_version"] == 1 else check_round_platformer
        problems.extend(check(label, events))

    print(f"{total} events, {len(sessions)} sessions, {len(rounds)} rounds")
    if problems:
        print(f"{len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("OK")
    return 0


def check_common(label: str, events: list[dict]) -> list[str]:
    """Checks shared by every version: framing, single start/end, ordered times."""
    problems = []
    names = [e["evento"] for e in events]
    if names[0] != "round_start":
        problems.append(f"round {label}: first event is {names[0]}, expected round_start")
    for name in ("round_start", "round_end"):
        if names.count(name) > 1:
            problems.append(f"round {label}: more than one {name}")
    if "round_end" not in names:
        problems.append(f"round {label}: no round_end")
    elif names[-1] != "round_end":
        problems.append(f"round {label}: events after round_end")
    times = [e["valor"]["t"] for e in events]
    if times != sorted(times):
        problems.append(f"round {label}: event times are not non-decreasing")
    return problems


def count_mismatches(label: str, events: list[dict], pairs: tuple[tuple[str, str], ...]) -> list[str]:
    names = [e["evento"] for e in events]
    if "round_end" not in names:
        return []
    end = events[names.index("round_end")]["valor"]
    return [
        f"round {label}: round_end.{field}={end[field]} but {names.count(event_name)} {event_name} events"
        for field, event_name in pairs
        if end[field] != names.count(event_name)
    ]


def check_round_v1(label: str, events: list[dict]) -> list[str]:
    """Arena version: at most one death, which comes before round_end."""
    problems = check_common(label, events)
    names = [e["evento"] for e in events]
    if names.count("player_death") > 1:
        problems.append(f"round {label}: more than one player_death")
    problems.extend(count_mismatches(label, events, (("coins_collected", "coin_collect"), ("position_samples", "player_position"))))
    return problems


def check_round_platformer(label: str, events: list[dict]) -> list[str]:
    """Versions 2 and 3: each death is followed by a respawn that restores every coin in place."""
    problems = check_common(label, events)
    names = [e["evento"] for e in events]
    problems.extend(count_mismatches(label, events, (
        ("coins_collected", "coin_collect"),
        ("position_samples", "player_position"),
        ("jumps", "player_jump"),
        ("deaths", "player_death"),
    )))
    dead = False
    for name in names:
        if name == "player_death":
            dead = True
        elif name == "player_respawn":
            dead = False
        elif dead and name not in ("coin_spawn", "round_end"):
            problems.append(f"round {label}: {name} recorded while the player was dead")
    if names.count("player_death") != names.count("player_respawn"):
        problems.append(f"round {label}: {names.count('player_death')} deaths but {names.count('player_respawn')} respawns")

    # Each attempt (initial start or respawn) spawns every coin exactly once.
    spawns = [e["valor"]["coin_id"] for e in events if e["evento"] == "coin_spawn"]
    attempts = 1 + names.count("player_respawn")
    if "round_end" in names:
        total = events[names.index("round_end")]["valor"]["coins_total"]
        if len(spawns) != total * attempts:
            problems.append(f"round {label}: {len(spawns)} coin_spawn events, expected {total} x {attempts} attempts")
        if any(spawns.count(i) != attempts for i in range(total)):
            problems.append(f"round {label}: coin_ids are not spawned once per attempt")
        positions: dict[int, set[tuple[float, float]]] = defaultdict(set)
        for e in events:
            if e["evento"] == "coin_spawn":
                positions[e["valor"]["coin_id"]].add((e["valor"]["x"], e["valor"]["y"]))
        moved = sorted(i for i, spots in positions.items() if len(spots) > 1)
        if moved:
            problems.append(f"round {label}: coins {moved} spawn at different places in different attempts")
        end = events[names.index("round_end")]["valor"]
        if end["completed"] and end["coins_collected"] < total:
            problems.append(f"round {label}: completed but only {end['coins_collected']} of {total} coins collected")
    return problems


if __name__ == "__main__":
    sys.exit(main())
