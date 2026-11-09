"""Runs the medallion pipeline: bronze (raw lines) -> silver (clean, typed) -> gold (metrics).

Usage:
    python -m pipeline.run_pipeline --raw pipeline/data/raw/synthetic --out pipeline/data/gold.json \\
        [--raw "<more files or folders>"] [--db pipeline/data/warehouse.duckdb] [--label "synthetic demo data"]

Every run rebuilds all three layers from the raw files (a full refresh), so running it twice gives the same result.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import duckdb

from pipeline import bronze, export_gold

SQL_DIR = Path(__file__).parent / "sql"


def run_layer(con, layer: str) -> None:
    for path in sorted((SQL_DIR / layer).glob("*.sql")):
        con.execute(path.read_text(encoding="utf-8"))


def run(con, sources: list[Path]) -> dict[str, int]:
    """Builds bronze, silver and gold in `con` and returns the row count of each layer."""
    bronze_lines = bronze.load(con, sources)
    run_layer(con, "silver")
    run_layer(con, "gold")
    count = lambda table: con.execute(f"select count(*) from {table}").fetchone()[0]
    return {
        "bronze lines": bronze_lines,
        "silver events": count("silver.events"),
        "silver quarantine": count("silver.quarantine"),
        "silver rounds": count("silver.rounds"),
        "gold days": count("gold.daily_metrics"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Bronze -> silver -> gold telemetry pipeline")
    parser.add_argument("--raw", type=Path, action="append", required=True, help="a .jsonl file or a folder of them (repeatable)")
    parser.add_argument("--db", type=Path, default=None, help="DuckDB file to keep (default: in memory)")
    parser.add_argument("--out", type=Path, default=None, help="write the gold tables as JSON here")
    parser.add_argument("--label", default="synthetic demo data", help="what the data is, shown next to the metrics")
    args = parser.parse_args()

    if args.db:
        args.db.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(args.db) if args.db else ":memory:")
    counts = run(con, args.raw)
    for layer, value in counts.items():
        print(f"{layer:>18}: {value:,}")
    if args.out:
        export_gold.export(con, args.out, args.label)
        print(f"gold exported to {args.out}")


if __name__ == "__main__":
    main()
