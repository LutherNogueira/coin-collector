# A bronze/silver/gold pipeline over the game's events, tested against synthetic ground truth

The game's event log is turned into metrics by a DuckDB pipeline in `pipeline/` with three layers: bronze keeps every line as received (broken lines included), silver parses, validates and conforms schema versions 2 to 4 and sends each rejected line to a quarantine table with exactly one reason, and gold holds the metrics. Every run rebuilds all layers from the raw files, so a rerun gives the same result.

Real logs are too few and too clean to prove the pipeline works, so a generator produces synthetic days with dirty rows added as *extra* lines (mutated or repeated copies of real ones) and writes a manifest with the true answers. The tests require bronze to keep every line, silver to keep exactly the clean lines, the quarantine reasons to equal what was injected, and gold to equal the manifest. This caught a real bug: numbering duplicates over all lines let a corrupted copy that came first make the genuine line look like the repeat, silently dropping good data. Duplicates are now numbered only among lines that passed every other rule.

Synthetic data is always labelled as such wherever it is shown. It is a stand-in for players, not evidence about them.
