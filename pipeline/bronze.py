"""Bronze layer: every line of every source file, exactly as it came, with where it came from.

Nothing is parsed, fixed or dropped here (broken lines and blank lines included). The raw text is the
record of what was received, so anything later layers reject can still be traced back to its line.
"""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

BATCH = 2000


def discover(sources: list[Path]) -> list[tuple[Path, str]]:
    """(path, label) for each .jsonl file; a directory contributes its files in name order."""
    found = []
    for source in sources:
        if source.is_dir():
            found.extend((path, f"{source.name}/{path.name}") for path in sorted(source.glob("*.jsonl")))
        elif source.is_file():
            found.append((source, source.name))
        else:
            raise FileNotFoundError(source)
    return found


def load(con, sources: list[Path]) -> int:
    """Recreates bronze.raw_events from the sources (a full refresh) and returns the row count."""
    con.execute("create schema if not exists bronze")
    con.execute("""
        create or replace table bronze.raw_events (
            source_file varchar,
            line_number integer,
            raw_line varchar,
            ingested_at timestamp
        )
    """)
    ingested_at = datetime.now(timezone.utc).replace(tzinfo=None)
    total = 0
    batch: list[tuple] = []
    for path, label in discover(sources):
        with open(path, "rb") as handle:
            for number, raw in enumerate(handle, start=1):
                batch.append((label, number, raw.decode("utf-8", errors="replace").rstrip("\r\n"), ingested_at))
                if len(batch) >= BATCH:
                    total += _insert(con, batch)
                    batch = []
    if batch:
        total += _insert(con, batch)
    return total


def _insert(con, rows: list[tuple]) -> int:
    placeholders = ",".join(["(?,?,?,?)"] * len(rows))
    con.execute(f"insert into bronze.raw_events values {placeholders}", [value for row in rows for value in row])
    return len(rows)
