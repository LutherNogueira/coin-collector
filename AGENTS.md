# Working agreement for coding agents

Rules for any agent (or person) changing this repository. They are written down because they were decided during the work, not because they are the default.

## Flow
- Work happens on `dev` or a `feature/*` branch. `main` only receives merges from `dev`, and every push to `main` deploys production.
- Do not commit, push or merge unless the owner asked for that step. Stage files by name: Godot rewrites `*.import` and `project.godot` line endings, and those changes are noise.
- Preview deploys exist for `dev` and `feature/**`; production is `main` only.

## Secrets and data
- No token, key or `.env*` file is ever committed (`.env.local` is git-ignored). Blob access in CI is a short-lived credential pulled from Vercel with the existing deploy secrets, never a stored Blob token.
- The game export bundles files from the project root, so a credentials file must be deleted before the export step. `pipeline/`, `tests/`, `tools/`, `docs/` and `ingest/` are excluded from the export.
- Raw event batches stay on the machine or runner that downloaded them. Only the aggregated `gold.json` is kept or published.
- Never claim data is "real players" without saying how many sessions there are: with few sessions it is mostly the author's own test plays (the statistics badge says so).

## Verifying a change
- Pipeline: `python -m unittest discover -s pipeline/tests -t .`
- Game: `godot --headless --path . --script res://tests/check_menu.gd` (also `check_stats`, `check_sender`, `check_touch`). Run them with a timeout: a test written against an old API can hang instead of failing.
- Endpoint: `cd ingest && npm test`. Node is not installed on the author's machine, so these tests only run in CI. Say so rather than calling them verified.
- Headless Godot has a 64x64 window, so tests feed input events straight to the node under test instead of through the viewport.
- What cannot be checked here (real phones, `sendBeacon` on a real tab close, the live Blob store) is reported as unchecked, not assumed.

## Decisions
Design choices are recorded as ADRs in `docs/adr/`; terms are in `GLOSSARY.md`. A change that reverses an ADR updates the ADR.
