"""Synthetic Coin Collector telemetry for the pipeline. These are NOT real players.

It writes one events_YYYY-MM-DD.jsonl per day in the same format as the game (schema versions 2, 3 and 4,
mixed the way releases overlap), plus a manifest.json with the ground truth. Optionally it adds dirty rows
on top of the clean events, so the pipeline has something to clean and the tests know the right answers:

    invalid_json, missing_field, invalid_timestamp, timestamp_out_of_range,
    unsupported_schema_version, unknown_event, value_out_of_range, duplicate

Dirty rows are always *extra* lines (mutated copies of real ones), so the metrics computed from the clean
rows must equal the manifest's truth whatever the dirt.

Usage: python -m pipeline.generate_synthetic --out pipeline/data/raw/synthetic [--days 40] [--end-date 2026-11-08]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import statistics
import uuid
from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

SAMPLE_INTERVAL = 0.5
DEATH_DELAY = 0.6
START_POS = (40.0, 532.0)
GENERATOR_VERSION = 2
GAME_EVENT_SEED_MAX = 2**31 - 1

# Share of extra dirty lines, relative to the number of clean lines of the day.
DIRT_RATES = {
    "invalid_json": 0.004,
    "missing_field": 0.003,
    "invalid_timestamp": 0.002,
    "timestamp_out_of_range": 0.002,
    "unsupported_schema_version": 0.002,
    "unknown_event": 0.002,
    "value_out_of_range": 0.003,
    "duplicate": 0.004,
}


def r1(value: float) -> float:
    return round(value, 1)


def r3(value: float) -> float:
    return round(value, 3)


def level_traits(level_seed: int) -> tuple[float, int]:
    """(difficulty 0..1, coin count) derived from the seed, standing in for the real level generator."""
    if level_seed == 0:
        return 0.35, 7
    h = (level_seed * 2654435761) % 2**32
    return (h % 1000) / 1000.0, 6 + (h >> 10) % 4


def new_uuid(rng: random.Random) -> str:
    return str(uuid.UUID(int=rng.getrandbits(128), version=4))


def stamp(moment: datetime) -> str:
    return moment.strftime("%Y-%m-%dT%H:%M:%S") + f".{moment.microsecond // 1000:03d}Z"


def encode(moment: datetime, evento: str, valor: dict, session_id: str, round_id: str | None, version: int) -> str:
    return json.dumps(
        {"timestamp": stamp(moment), "evento": evento, "valor": valor, "session_id": session_id,
         "round_id": round_id, "schema_version": version},
        sort_keys=True, separators=(",", ":"),
    )


def simulate_round(rng: random.Random, level_seed: int, skill: float, version: int):
    """One round as (events, record). Events are (seconds since round start, name, valor)."""
    difficulty, coins_total = level_traits(level_seed)
    round_id = new_uuid(rng)
    coin_xy = [(r1(rng.uniform(40, 760)), r1(rng.uniform(260, 520))) for _ in range(coins_total)]
    events: list[tuple[float, str, dict]] = []

    start_valor: dict = {"t": 0.0}
    if version >= 3:
        start_valor["level_seed"] = level_seed
    if version >= 4:
        start_valor["generator_version"] = GENERATOR_VERSION
    events.append((0.0, "round_start", start_valor))

    t = 0.0
    attempts = deaths = jumps = samples = collected_total = 0
    causes: list[str] = []
    completed = False
    x = START_POS[0]
    while True:
        attempts += 1
        attempt_start = t
        for i, (cx, cy) in enumerate(coin_xy):
            events.append((t, "coin_spawn", {"t": r3(t), "coin_id": i, "x": cx, "y": cy}))
        if attempts > 1:
            events.append((t, "player_respawn", {"t": r3(t), "x": START_POS[0], "y": START_POS[1]}))

        quit_probability = 0.04 + 0.05 * deaths
        win_probability = min(max((1.0 - 0.8 * difficulty) * skill * (1.0 + 0.1 * (attempts - 1)), 0.05), 0.95)
        if rng.random() < quit_probability:
            outcome = "quit"
        elif rng.random() < win_probability:
            outcome = "win"
        else:
            outcome = "death"
        end_t = t + (rng.uniform(25, 75) if outcome == "win" else rng.uniform(3, 45))

        # Position samples every half second while alive.
        sample_t = (math.floor(t / SAMPLE_INTERVAL) + 1) * SAMPLE_INTERVAL
        while sample_t <= end_t:
            x = min(max(x + rng.uniform(-70, 90), 12.0), 788.0)
            y = 532.0 if rng.random() < 0.7 else rng.uniform(380, 532)
            events.append((sample_t, "player_position", {"t": r3(sample_t), "x": r1(x), "y": r1(y)}))
            samples += 1
            sample_t += SAMPLE_INTERVAL

        # Jumps, each followed by a landing.
        jump_t = attempt_start + rng.uniform(0.3, 1.5)
        while jump_t < end_t - 0.1:
            jx = r1(min(max(x + rng.uniform(-30, 30), 12.0), 788.0))
            events.append((jump_t, "player_jump", {"t": r3(jump_t), "x": jx, "y": 532.0}))
            jumps += 1
            land_t = jump_t + rng.uniform(0.45, 0.8)
            if land_t <= end_t:
                events.append((land_t, "player_land", {"t": r3(land_t), "x": jx, "y": 532.0, "vy": r1(rng.uniform(250, 520))}))
            jump_t = max(land_t, jump_t) + rng.expovariate(1 / 1.2)

        # Coins taken in this attempt (all of them when it is won; the last one at the moment of the win).
        taken = coins_total if outcome == "win" else rng.randint(0, coins_total - 1)
        times = sorted(rng.uniform(attempt_start + 1.0, end_t) for _ in range(taken))
        if outcome == "win" and times:
            times[-1] = end_t
        for coin_id, take_t in zip(rng.sample(range(coins_total), taken), times):
            cx, cy = coin_xy[coin_id]
            events.append((take_t, "coin_collect", {"t": r3(take_t), "coin_id": coin_id, "x": cx, "y": cy,
                                                    "dt": r3(take_t - attempt_start)}))
        collected_total += taken

        if outcome == "win":
            completed = True
            t = end_t
            break
        if outcome == "quit":
            t = end_t
            break

        # Death: by a trap or by falling into a pit.
        cause = "pit" if rng.random() < 0.35 else "trap"
        events.append((end_t, "player_death", {"t": r3(end_t), "x": r1(x), "y": r1(rng.uniform(612, 700)) if cause == "pit" else 528.0,
                                               "cause": cause}))
        deaths += 1
        causes.append(cause)
        if rng.random() < 0.12:   # the window is closed while the player is dead
            t = end_t + rng.uniform(0.1, DEATH_DELAY - 0.05)
            break
        t = end_t + DEATH_DELAY

    events.append((t, "round_end", {"t": r3(t), "completed": completed, "coins_collected": collected_total,
                                    "coins_total": coins_total, "deaths": deaths, "jumps": jumps,
                                    "position_samples": samples, "duration_s": r3(t)}))
    events.sort(key=lambda e: e[0])   # stable, so events with the same time keep their order
    record = {"level_seed": level_seed, "completed": completed, "attempts": 1 + sum(1 for e in events if e[1] == "player_respawn"),
              "deaths": deaths, "causes": causes, "duration_s": r3(t)}
    return round_id, events, record


def simulate_day(rng: random.Random, day: date, day_index: int, total_days: int):
    """All the lines of one day (as (datetime, order, text)) and the day's round records."""
    fraction = day_index / max(total_days - 1, 1)
    base_version = 2 if fraction < 0.3 else 3 if fraction < 0.6 else 4
    weekend = day.weekday() >= 5
    session_count = max(1, round(rng.gauss(5 + 0.12 * day_index + (3 if weekend else 0), 1.5)))

    lines: list[tuple[datetime, int, str]] = []
    records: list[dict] = []
    order = 0
    for _ in range(session_count):
        version = max(2, base_version - 1) if rng.random() < 0.1 else base_version   # a stale client
        session_id = new_uuid(rng)
        start = datetime.combine(day, time(6, 0), tzinfo=timezone.utc) + timedelta(seconds=rng.uniform(0, 15 * 3600))
        skill = rng.uniform(0.7, 1.3)
        lines.append((start, order, encode(start, "session_start", {}, session_id, None, version)))
        order += 1
        cursor = start
        for index in range(rng.choice([1, 1, 2, 2, 3, 4])):
            level_seed = 0 if index == 0 or version == 2 else rng.randint(1, GAME_EVENT_SEED_MAX)
            round_id, events, record = simulate_round(rng, level_seed, skill, version)
            for seconds, name, valor in events:
                moment = cursor + timedelta(seconds=seconds)
                lines.append((moment, order, encode(moment, name, valor, session_id, round_id, version)))
                order += 1
            record.update(day=day.isoformat(), session_id=session_id, schema_version=version)
            records.append(record)
            cursor += timedelta(seconds=record["duration_s"] + rng.uniform(4, 25))
        lines.append((cursor, order, encode(cursor, "session_end", {}, session_id, None, version)))
        order += 1
    lines.sort(key=lambda item: (item[0], item[1]))
    return lines, records


def inject_dirt(clean: list[str], rng: random.Random, injected: Counter) -> list[str]:
    """Adds extra dirty lines (mutated or repeated copies of clean ones) at random places."""
    extras: list[str] = []
    for reason, rate in DIRT_RATES.items():
        for _ in range(round(len(clean) * rate)):
            base = clean[rng.randrange(len(clean))]
            data = json.loads(base)
            if reason == "invalid_json":
                extras.append(base[: rng.randint(10, len(base) - 5)])   # a truncated object is never valid JSON
            elif reason == "duplicate":
                extras.append(base)
            else:
                if reason == "missing_field":
                    key = rng.choice(["session_id", "evento", "timestamp", "schema_version"])
                    if rng.random() < 0.5:
                        del data[key]
                    else:
                        data[key] = None
                elif reason == "invalid_timestamp":
                    data["timestamp"] = rng.choice(["2026-13-45T25:61:61.000Z", "not-a-date", "31/10/2026 12:00", "2026-02-30T10:00:00.000Z"])
                elif reason == "timestamp_out_of_range":
                    data["timestamp"] = rng.choice(["1970-01-01T00:00:00.000Z", "2099-01-01T00:00:00.000Z", "2001-09-09T01:46:40.000Z"])
                elif reason == "unsupported_schema_version":
                    data["schema_version"] = rng.choice([1, 5, 99])
                elif reason == "unknown_event":
                    data["evento"] = rng.choice(["player_teleport", "coin_collected", ""])
                elif reason == "value_out_of_range":
                    candidates = [i for i, text in enumerate(clean) if '"x":' in text]
                    data = json.loads(clean[rng.choice(candidates)])
                    data["valor"]["x"] = rng.choice([9999, -50])
                extras.append(json.dumps(data, sort_keys=True, separators=(",", ":")))
            injected[reason] += 1
    merged = clean + extras
    positions = sorted(range(len(merged)), key=lambda i: (i if i < len(clean) else rng.uniform(0, len(clean)), i))
    return [merged[i] for i in positions]


def generate(out_dir: Path, days: int = 40, end_date: date | None = None, seed: int = 7, dirt: bool = True) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    end_date = end_date or datetime.now(timezone.utc).date()
    rng = random.Random(seed)
    dirt_rng = random.Random(seed ^ 0xD127)   # its own stream, so the clean events do not depend on the dirt
    injected: Counter = Counter()
    records_by_day: dict[str, list[dict]] = {}
    total_lines = clean_lines = 0

    for index in range(days):
        day = end_date - timedelta(days=days - 1 - index)
        lines, records = simulate_day(rng, day, index, days)
        clean = [text for _, _, text in lines]
        final = inject_dirt(clean, dirt_rng, injected) if dirt else clean
        (out_dir / f"events_{day.isoformat()}.jsonl").write_text("\n".join(final) + "\n", encoding="utf-8")
        records_by_day[day.isoformat()] = records
        total_lines += len(final)
        clean_lines += len(clean)

    manifest = {
        "note": "Synthetic demo data, not real players.",
        "seed": seed,
        "dirt": dirt,
        "total_lines": total_lines,
        "clean_lines": clean_lines,
        "injected": dict(injected),
        "truth": truth(records_by_day),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def truth(records_by_day: dict[str, list[dict]]) -> dict:
    """What the metrics must be, computed straight from the simulated rounds."""
    daily = []
    causes: Counter = Counter()
    all_records = []
    for day, records in sorted(records_by_day.items()):
        completed_durations = [r["duration_s"] for r in records if r["completed"]]
        for record in records:
            causes.update(record["causes"])
        all_records.extend(records)
        daily.append({
            "day": day,
            "sessions": len({r["session_id"] for r in records}),
            "rounds": len(records),
            "completed_rounds": sum(1 for r in records if r["completed"]),
            "attempts": sum(r["attempts"] for r in records),
            "deaths": sum(r["deaths"] for r in records),
            "avg_duration_completed_s": statistics.fmean(completed_durations) if completed_durations else None,
            "median_duration_completed_s": statistics.median(completed_durations) if completed_durations else None,
        })
    by_level: dict[int, dict] = defaultdict(lambda: {"attempts": 0, "deaths": 0})
    for record in all_records:
        by_level[record["level_seed"]]["attempts"] += record["attempts"]
        by_level[record["level_seed"]]["deaths"] += record["deaths"]
    return {
        "daily": daily,
        "deaths_by_cause": dict(causes),
        "total_rounds": len(all_records),
        "total_attempts": sum(r["attempts"] for r in all_records),
        "total_deaths": sum(r["deaths"] for r in all_records),
        "level_0": by_level[0],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--days", type=int, default=40)
    parser.add_argument("--end-date", type=date.fromisoformat, default=None, help="last day (default: today, UTC)")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--no-dirt", action="store_true", help="write only clean events")
    args = parser.parse_args()
    manifest = generate(args.out, args.days, args.end_date, args.seed, dirt=not args.no_dirt)
    print(f"{manifest['total_lines']} lines in {args.days} files ({manifest['clean_lines']} clean, "
          f"{sum(manifest['injected'].values())} dirty) -> {args.out}")


if __name__ == "__main__":
    main()
