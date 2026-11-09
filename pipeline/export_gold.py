"""Exports the gold tables as one JSON file, the only thing the metrics screen reads."""
from __future__ import annotations

import json
from datetime import date, datetime, timezone
from pathlib import Path

TABLES = ["daily_metrics", "deaths_by_cause", "deadliest_levels", "data_quality"]


def _rows(con, table: str) -> list[dict]:
    cursor = con.execute(f"select * from gold.{table}")
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, row)) for row in cursor.fetchall()]


def _json_default(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f"cannot serialize {type(value).__name__}")


def build(con, source_label: str) -> dict:
    summary = _rows(con, "summary")[0]
    return {
        "meta": {
            "source": source_label,
            "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "layers": "bronze -> silver -> gold",
        },
        "summary": summary,
        **{table: _rows(con, table) for table in TABLES},
    }


def export(con, out_path: Path, source_label: str) -> dict:
    document = build(con, source_label)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(document, indent=2, default=_json_default), encoding="utf-8")
    return document
