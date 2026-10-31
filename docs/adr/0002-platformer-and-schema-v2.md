# Platformer with fixed level, and schema version 2

The game changed from an arena with moving obstacles to a one-screen platformer with gravity, jumping, fixed solids, fixed traps and fixed coins, because physics produces richer events (jumps, landings, impact speed) and a fixed level makes rounds comparable. Dying restarts the level from the start point inside the same round, there is no time limit, and a round is complete when every coin is collected in one attempt.

This breaks the v1 event contract (new events and fields, `obstacles_spawned` removed, `round_end` reshaped), so the logger now writes `schema_version: 2`. The v1 schema is kept as `schema/events.v1.schema.json` and the validator picks the schema from each line's `schema_version`, so logs recorded by the arena version remain valid.

Physics is a small hand-written kinematic simulation (gravity, axis-separated rectangle collisions in fixed substeps) instead of Godot's physics nodes. It keeps the game logic input-free and deterministic, so it can be driven and tested without a window.
