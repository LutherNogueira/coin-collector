# Event payload is an object with one schema per event type

Every event line keeps the same top-level fields (`timestamp`, `evento`, `valor`, `session_id`, `round_id`, `schema_version`), and `valor` is always an object whose shape depends on `evento`. We chose this over flat columns with `null` for inapplicable fields because each event type is then described separately by the JSON Schema, which is the point of the project; the cost is that consumers must flatten `valor` themselves.

The end of a round is derived from the presence of a `player_death` event rather than a `reason` field on `round_end`, which only carries counters.

Update: the second paragraph describes schema version 1. In version 2 a round has no timeout, so `round_end` carries a `completed` flag instead (see ADR 0002).
