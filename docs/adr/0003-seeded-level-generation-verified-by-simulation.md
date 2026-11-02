# Levels are generated from a seed and verified by simulating the player

After the first round (which plays the hand-made level, seed 0), each round plays a level generated from a random seed, and `round_start` records that seed in schema version 3. Generating from a seed instead of drawing a random level on the fly means a round's layout can always be rebuilt from the log, which keeps rounds analyzable even though they are no longer comparable by position.

The generator uses placement rules to stay within jump range, but rules alone do not prove a level is completable. Completability is checked offline by `tests/verify_levels.gd`, which explores what the player can reach with the same physics as the game and requires every coin to be touchable on a path where the player survives. We did not run this check at runtime, to keep level creation instant; the cost is that an unverified seed could in principle be unfinishable, so the check is run over many seeds instead.

Considered options: building levels from a hand-authored library of chunks (more predictable, but a fixed vocabulary of layouts) and rejecting unsolvable seeds at runtime with the solver (a guarantee, but a noticeable pause for each level).
