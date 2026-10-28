"""Validate an events.jsonl file against schema/events.schema.json.

Besides the JSON Schema check on every line, it verifies per-round consistency:
a round starts once, ends at most once, has at most one death, and the
`round_end` counters match the events actually recorded.

Usage: python validate_events.py [path/to/events.jsonl]
"""
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA_PATH = Path(__file__).parent / "schema" / "events.schema.json"
DEFAULT_LOG = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "Coin Collector" / "events.jsonl"


def main() -> int:
    log_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_LOG
    if not log_path.is_file():
        print(f"File not found: {log_path}")
        return 2

    validator = Draft202012Validator(json.loads(SCHEMA_PATH.read_text(encoding="utf-8")))
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
        errors = sorted(validator.iter_errors(event), key=lambda e: list(e.path))
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
        problems.extend(check_round(round_id[:8], events))

    print(f"{total} events, {len(sessions)} sessions, {len(rounds)} rounds")
    if problems:
        print(f"{len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("OK")
    return 0


def check_round(label: str, events: list[dict]) -> list[str]:
    problems = []
    names = [e["evento"] for e in events]
    if names[0] != "round_start":
        problems.append(f"round {label}: first event is {names[0]}, expected round_start")
    for name in ("round_start", "round_end", "player_death"):
        if names.count(name) > 1:
            problems.append(f"round {label}: more than one {name}")
    if "round_end" not in names:
        problems.append(f"round {label}: no round_end")
        return problems
    if names[-1] != "round_end":
        problems.append(f"round {label}: events after round_end")
    if "player_death" in names and names.index("player_death") > names.index("round_end"):
        problems.append(f"round {label}: player_death after round_end")

    end = events[names.index("round_end")]["valor"]
    for field, event_name in (("coins_collected", "coin_collect"), ("position_samples", "player_position")):
        if end[field] != names.count(event_name):
            problems.append(f"round {label}: round_end.{field}={end[field]} but {names.count(event_name)} {event_name} events")
    times = [e["valor"]["t"] for e in events]
    if times != sorted(times):
        problems.append(f"round {label}: event times are not non-decreasing")
    return problems


if __name__ == "__main__":
    sys.exit(main())
