# Levels sit on a 16 px tile grid, and the logged level carries a generator version

To draw terrain, spikes and coins with tile art, every solid and trap now sits on a 16 px grid (platforms are 32 px thick, spikes are whole tiles, the ground runs off the bottom of the screen). This changed the hand-made level and the generator, so a given seed now produces a different level than before. Schema version 4 therefore adds `generator_version` to `round_start`, and `Level.GENERATOR_VERSION` must be bumped whenever the level code changes; a seed alone no longer identifies a level. Schema 3 logs correspond to generator version 1, which never logged it.

Collision shapes stay independent of the art: the player is still a 24x24 box and coins are 12 px circles. The one exception is spikes, whose lethal area is only the lower half of the tile because that is all the spike art fills; this only removes lethal area, so levels verified before the change stay completable.
