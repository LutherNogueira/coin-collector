"""Checks the medallion pipeline against ground truth.

The synthetic generator knows the right answers (manifest.json), so each test compares what bronze, silver and
gold produced with what must be true. Run from the repository root:

    python -m unittest discover -s pipeline/tests -t .
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

import duckdb

from pipeline import generate_synthetic, run_pipeline

ROOT = Path(__file__).resolve().parents[2]
SESSION = "11111111-1111-4111-8111-111111111111"
SESSION_START = ('{"evento":"session_start","round_id":null,"schema_version":4,"session_id":"%s",'
                 '"timestamp":"2026-10-01T10:00:00.000Z","valor":{}}' % SESSION)


class SyntheticDataTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        base = Path(cls.tmp.name)
        end = date(2026, 10, 20)
        cls.clean_dir = base / "clean"
        cls.dirty_dir = base / "dirty"
        cls.clean = generate_synthetic.generate(cls.clean_dir, days=8, end_date=end, seed=11, dirt=False)
        cls.manifest = generate_synthetic.generate(cls.dirty_dir, days=8, end_date=end, seed=11, dirt=True)
        cls.con = duckdb.connect(":memory:")
        cls.counts = run_pipeline.run(cls.con, [cls.dirty_dir])

    @classmethod
    def tearDownClass(cls):
        cls.con.close()
        cls.tmp.cleanup()

    def rows(self, sql: str) -> list[tuple]:
        return self.con.execute(sql).fetchall()

    # --- the synthetic data itself -------------------------------------------------------------------------

    def test_clean_synthetic_events_pass_the_game_validator(self):
        for path in sorted(self.clean_dir.glob("*.jsonl")):
            result = subprocess.run([sys.executable, str(ROOT / "validate_events.py"), str(path)],
                                    capture_output=True, text=True, cwd=ROOT)
            self.assertEqual(result.returncode, 0, f"{path.name}:\n{result.stdout}")

    def test_dirt_does_not_change_the_clean_events(self):
        self.assertEqual(self.clean["truth"], self.manifest["truth"])

    # --- bronze and silver ---------------------------------------------------------------------------------

    def test_bronze_keeps_every_line(self):
        self.assertEqual(self.counts["bronze lines"], self.manifest["total_lines"])

    def test_silver_keeps_exactly_the_clean_lines(self):
        self.assertEqual(self.counts["silver events"], self.manifest["clean_lines"])

    def test_quarantine_reasons_match_what_was_injected(self):
        got = dict(self.rows("select reject_reason, count(*) from silver.quarantine group by 1"))
        self.assertEqual(got, self.manifest["injected"])

    def test_every_quarantined_line_traces_back_to_bronze(self):
        orphans = self.rows("""
            select count(*) from silver.quarantine q
            left join bronze.raw_events b using (source_file, line_number)
            where b.raw_line is null or b.raw_line <> q.raw_line""")
        self.assertEqual(orphans[0][0], 0)

    # --- gold ----------------------------------------------------------------------------------------------

    def test_daily_metrics_match_the_truth(self):
        gold = {str(row[0]): row for row in self.rows("""
            select day, sessions, rounds, completed_rounds, attempts, deaths, completion_rate, death_rate,
                   avg_duration_completed_s, median_duration_completed_s
            from gold.daily_metrics""")}
        self.assertEqual(sorted(gold), [d["day"] for d in self.manifest["truth"]["daily"]])
        for expected in self.manifest["truth"]["daily"]:
            _, sessions, rounds, completed, attempts, deaths, completion_rate, death_rate, avg_s, median_s = gold[expected["day"]]
            label = expected["day"]
            self.assertEqual((sessions, rounds, completed, attempts, deaths),
                             (expected["sessions"], expected["rounds"], expected["completed_rounds"],
                              expected["attempts"], expected["deaths"]), label)
            self.assertAlmostEqual(completion_rate, expected["completed_rounds"] / expected["rounds"], places=3, msg=label)
            self.assertAlmostEqual(death_rate, expected["deaths"] / expected["attempts"], places=3, msg=label)
            if expected["avg_duration_completed_s"] is None:
                self.assertIsNone(avg_s, label)
            else:
                self.assertAlmostEqual(avg_s, expected["avg_duration_completed_s"], places=2, msg=label)
                self.assertAlmostEqual(median_s, expected["median_duration_completed_s"], places=2, msg=label)

    def test_summary_matches_the_truth(self):
        truth = self.manifest["truth"]
        rounds, attempts, deaths, death_rate, bronze, silver, quarantined = self.rows("""
            select rounds, attempts, deaths, death_rate, bronze_lines, silver_events, quarantined_lines
            from gold.summary""")[0]
        self.assertEqual((rounds, attempts, deaths), (truth["total_rounds"], truth["total_attempts"], truth["total_deaths"]))
        self.assertAlmostEqual(death_rate, truth["total_deaths"] / truth["total_attempts"], places=3)
        self.assertEqual(bronze, silver + quarantined)

    def test_deaths_by_cause_match_the_truth(self):
        got = dict(self.rows("select cause, deaths from gold.deaths_by_cause"))
        self.assertEqual(got, self.manifest["truth"]["deaths_by_cause"])

    def test_death_rate_never_exceeds_one(self):
        self.assertEqual(self.rows("select count(*) from gold.daily_metrics where death_rate > 1")[0][0], 0)

    def test_running_twice_gives_the_same_gold(self):
        again = duckdb.connect(":memory:")
        try:
            run_pipeline.run(again, [self.dirty_dir])
            for table in ("daily_metrics", "deaths_by_cause", "deadliest_levels", "data_quality"):
                sql = f"select * from gold.{table} order by all"
                self.assertEqual(self.con.execute(sql).fetchall(), again.execute(sql).fetchall(), table)
        finally:
            again.close()


class SilverRulesTest(unittest.TestCase):
    """Small hand-made files for the rules that matter most."""

    def run_lines(self, lines: list[str]) -> duckdb.DuckDBPyConnection:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        (Path(tmp.name) / "events.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
        con = duckdb.connect(":memory:")
        self.addCleanup(con.close)
        run_pipeline.run(con, [Path(tmp.name)])
        return con

    def reasons(self, con) -> dict:
        return dict(con.execute("select reject_reason, count(*) from silver.quarantine group by 1").fetchall())

    def test_a_corrupted_copy_before_the_original_does_not_cost_the_original(self):
        # The copy without schema_version comes first in the file; the genuine line must still survive.
        corrupted = SESSION_START.replace('"schema_version":4,', "")
        con = self.run_lines([corrupted, SESSION_START])
        self.assertEqual(con.execute("select count(*) from silver.events").fetchone()[0], 1)
        self.assertEqual(self.reasons(con), {"missing_field": 1})

    def test_an_exact_repeat_is_a_duplicate_and_the_first_copy_is_kept(self):
        con = self.run_lines([SESSION_START, SESSION_START])
        self.assertEqual(con.execute("select count(*) from silver.events").fetchone()[0], 1)
        self.assertEqual(con.execute("select line_number from silver.quarantine").fetchone()[0], 2)
        self.assertEqual(self.reasons(con), {"duplicate": 1})

    def test_text_that_is_not_a_json_object_is_rejected_without_crashing(self):
        con = self.run_lines(["", "   ", "[1, 2]", '"just text"', "42", "{broken", SESSION_START])
        self.assertEqual(con.execute("select count(*) from silver.events").fetchone()[0], 1)
        self.assertEqual(self.reasons(con), {"invalid_json": 6})

    def test_schema_versions_two_to_four_are_conformed_and_one_is_rejected(self):
        def round_start(version: int, extra: str, round_id: str) -> str:
            return ('{"evento":"round_start","round_id":"%s","schema_version":%d,"session_id":"%s",'
                    '"timestamp":"2026-10-01T10:00:0%d.000Z","valor":{"t":0.0%s}}' % (round_id, version, SESSION, version % 10, extra))
        lines = [
            round_start(2, "", "22222222-2222-4222-8222-222222222222"),
            round_start(3, ',"level_seed":123', "33333333-3333-4333-8333-333333333333"),
            round_start(4, ',"level_seed":456,"generator_version":2', "44444444-4444-4444-8444-444444444444"),
            round_start(1, "", "55555555-5555-4555-8555-555555555555"),
        ]
        con = self.run_lines(lines)
        got = con.execute("select schema_version, level_seed, generator_version from silver.events order by schema_version").fetchall()
        self.assertEqual(got, [(2, 0, 1), (3, 123, 1), (4, 456, 2)])
        self.assertEqual(self.reasons(con), {"unsupported_schema_version": 1})


if __name__ == "__main__":
    unittest.main()
