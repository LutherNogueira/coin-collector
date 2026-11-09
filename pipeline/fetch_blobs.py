"""Downloads the event batches the web build uploaded to Vercel Blob, as the source files of the bronze layer.

    python -m pipeline.fetch_blobs --out pipeline/data/raw/real
    python -m pipeline.run_pipeline --raw pipeline/data/raw/real --out stats/data/gold.json --label "real plays"

Every batch is its own blob (events/<day>/<session>-<random>.jsonl) and blobs are never overwritten, so a batch
that is already on disk is skipped: running this again only fetches what is new. Nothing is parsed or changed
here, which is bronze's rule too; bad lines are for the silver layer to quarantine.

Credentials come from the environment, and from a git-ignored `.env.local` next to where you run it:
    BLOB_READ_WRITE_TOKEN   the token Vercel created when the store was connected (Settings > Environment Variables)
Needs the Vercel SDK for Python: pip install -r pipeline/requirements-fetch.txt
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Callable, Iterable

PREFIX = "events/"
ENV_FILE = ".env.local"
ENV_KEYS = ("BLOB_READ_WRITE_TOKEN", "BLOB_STORE_ID", "VERCEL_OIDC_TOKEN")


def local_name(pathname: str) -> str:
    """events/2026-11-09/<session>-<random>.jsonl -> 2026-11-09__<session>-<random>.jsonl (flat, sorts by day)."""
    parts = pathname.removeprefix(PREFIX).split("/")
    if not pathname.startswith(PREFIX) or len(parts) != 2 or not parts[1].endswith(".jsonl") or ".." in pathname:
        raise ValueError(f"not an event batch: {pathname!r}")
    return f"{parts[0]}__{parts[1]}"


def session_of(pathname: str) -> str:
    """The session id a batch belongs to (the 36 characters at the start of the file name)."""
    return pathname.rsplit("/", 1)[-1][:36]


def sync(blobs: Iterable[str], fetch: Callable[[str], bytes], out: Path, skip_sessions: set[str] | None = None) -> dict:
    """Saves the batches in `blobs` (pathnames) that are not in `out` yet. `fetch` returns a batch's bytes."""
    skip_sessions = skip_sessions or set()
    out.mkdir(parents=True, exist_ok=True)
    result = {"downloaded": 0, "already_there": 0, "skipped_sessions": 0, "ignored": 0}
    for pathname in blobs:
        try:
            name = local_name(pathname)
        except ValueError:
            result["ignored"] += 1
            continue
        if session_of(pathname) in skip_sessions:
            result["skipped_sessions"] += 1
            continue
        target = out / name
        if target.exists():
            result["already_there"] += 1
            continue
        partial = target.with_suffix(".part")
        partial.write_bytes(fetch(pathname))
        partial.replace(target)   # a half-written file never looks like a finished batch
        result["downloaded"] += 1
    return result


def load_env_file(path: Path = Path(ENV_FILE)) -> None:
    """Reads KEY=VALUE lines for the Blob credentials from a local file, without overriding the environment."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        key, sep, value = line.strip().partition("=")
        if sep and key in ENV_KEYS and key not in os.environ:
            os.environ[key] = value.strip().strip('"').strip("'")


def main() -> int:
    parser = argparse.ArgumentParser(description="Download the uploaded event batches from Vercel Blob")
    parser.add_argument("--out", type=Path, required=True, help="folder for the .jsonl batches (the bronze source)")
    parser.add_argument("--skip-session", action="append", default=[], metavar="ID",
                        help="leave out the batches of this session id (repeatable), e.g. a test upload")
    args = parser.parse_args()

    load_env_file()
    if not (os.environ.get("BLOB_READ_WRITE_TOKEN") or os.environ.get("BLOB_STORE_ID")):
        print(f"No Blob credentials: set BLOB_READ_WRITE_TOKEN in the environment or in {ENV_FILE}.", file=sys.stderr)
        return 2
    try:
        from vercel.blob import sync as blob
    except ImportError:
        print("The Vercel SDK is missing: pip install -r pipeline/requirements-fetch.txt", file=sys.stderr)
        return 2

    def fetch(pathname: str) -> bytes:
        return blob.get_blob(pathname, access="private").body

    names = (item.pathname for item in blob.query_blobs(prefix=PREFIX))
    result = sync(names, fetch, args.out, set(args.skip_session))
    print(f"downloaded {result['downloaded']} new batch(es); {result['already_there']} already in {args.out}"
          f"; {result['skipped_sessions']} skipped by session; {result['ignored']} ignored (not event batches)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
