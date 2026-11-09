"""Checks the Blob downloader without any network: it is given fake blob names and a fake `fetch`."""
from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from pipeline import fetch_blobs

S1 = "11111111-1111-4111-8111-111111111111"
S2 = "22222222-2222-4222-8222-222222222222"
A = f"events/2026-11-09/{S1}-abc123.jsonl"
B = f"events/2026-11-10/{S2}-def456.jsonl"


class FetchBlobsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "raw"
        self.fetched: list[str] = []

    def tearDown(self):
        self.tmp.cleanup()

    def fetch(self, pathname: str) -> bytes:
        self.fetched.append(pathname)
        return f"content of {pathname}\n".encode()

    def test_names_are_flat_and_sort_by_day(self):
        self.assertEqual(fetch_blobs.local_name(A), f"2026-11-09__{S1}-abc123.jsonl")
        self.assertEqual(fetch_blobs.session_of(A), S1)

    def test_only_event_batches_are_accepted(self):
        for bad in ("other/x.jsonl", "events/x.jsonl", "events/2026-11-09/x.txt", "events/../x/y.jsonl",
                    "events/2026-11-09/sub/y.jsonl"):
            with self.assertRaises(ValueError, msg=bad):
                fetch_blobs.local_name(bad)

    def test_downloads_new_batches_and_ignores_other_blobs(self):
        result = fetch_blobs.sync([A, "readme.txt", B], self.fetch, self.out)
        self.assertEqual(result, {"downloaded": 2, "already_there": 0, "skipped_sessions": 0, "ignored": 1})
        self.assertEqual(sorted(p.name for p in self.out.iterdir()), sorted(fetch_blobs.local_name(x) for x in (A, B)))
        self.assertEqual((self.out / fetch_blobs.local_name(A)).read_bytes(), f"content of {A}\n".encode())

    def test_running_again_fetches_only_what_is_new(self):
        fetch_blobs.sync([A], self.fetch, self.out)
        self.fetched.clear()
        result = fetch_blobs.sync([A, B], self.fetch, self.out)
        self.assertEqual(self.fetched, [B])
        self.assertEqual((result["downloaded"], result["already_there"]), (1, 1))

    def test_a_skipped_session_is_not_downloaded(self):
        result = fetch_blobs.sync([A, B], self.fetch, self.out, skip_sessions={S1})
        self.assertEqual(self.fetched, [B])
        self.assertEqual((result["downloaded"], result["skipped_sessions"]), (1, 1))

    def test_a_failed_download_leaves_no_finished_file(self):
        def failing(_pathname: str) -> bytes:
            raise RuntimeError("network down")
        with self.assertRaises(RuntimeError):
            fetch_blobs.sync([A], failing, self.out)
        self.assertEqual(list(self.out.glob("*.jsonl")), [])

    def test_the_env_file_fills_missing_credentials_only(self):
        env_file = Path(self.tmp.name) / ".env.local"
        env_file.write_text('# comment\nBLOB_READ_WRITE_TOKEN="from-file"\nOTHER=ignored\nBLOB_STORE_ID=store_1\n', encoding="utf-8")
        saved = {k: os.environ.pop(k, None) for k in fetch_blobs.ENV_KEYS}
        try:
            os.environ["BLOB_STORE_ID"] = "already-set"
            fetch_blobs.load_env_file(env_file)
            self.assertEqual(os.environ["BLOB_READ_WRITE_TOKEN"], "from-file")
            self.assertEqual(os.environ["BLOB_STORE_ID"], "already-set")
            self.assertNotIn("OTHER", os.environ)
        finally:
            for key, value in saved.items():
                os.environ.pop(key, None)
                if value is not None:
                    os.environ[key] = value


if __name__ == "__main__":
    unittest.main()
