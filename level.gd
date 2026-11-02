class_name Level
extends RefCounted
## A one-screen level: solid blocks, traps and coins. Level 0 is hand-made; any other seed is generated.
## Every solid and trap sits on a 16 px grid so tile art lines up (the ground runs off the bottom edge).

const ARENA := Vector2(800, 600)
const TILE := 16.0
const GROUND_TOP := 544.0
const START_POS := Vector2(40, 532)
const PLATFORM_THICKNESS := 32.0
const COIN_RADIUS := 12.0
## The spike art only fills the bottom half of its tile, so only that half is lethal.
const TRAP_INSET := 8.0
## Bump whenever the hand-made level or the generator changes, so a logged seed can be tied to the code
## that built it. Version 1 was the generator without the tile grid (schema 3 logs); it never logged this.
const GENERATOR_VERSION := 2
## A platform whose bottom is below this is "low": it caps the jump of anyone under or beside it.
const LOW_BOTTOM := 456.0

var seed_value := 0
var solids: Array[Rect2] = []
var traps: Array[Rect2] = []
var coins: Array[Vector2] = []


static func hand_made() -> Level:
	var lvl := Level.new()
	lvl.solids = [
		Rect2(0, 544, 304, 56),
		Rect2(384, 544, 176, 56),
		Rect2(640, 544, 160, 56),
		Rect2(448, 480, 32, 64),
		Rect2(176, 464, 112, 32),
		Rect2(336, 384, 112, 32),
		Rect2(528, 320, 96, 32),
		Rect2(656, 432, 112, 32),
	]
	lvl.traps = [
		Rect2(96, 528, 48, 16),
		Rect2(496, 528, 32, 16),
		Rect2(704, 416, 16, 16),
	]
	lvl.coins = [
		Vector2(120, 474),
		Vector2(232, 442),
		Vector2(344, 474),
		Vector2(392, 362),
		Vector2(576, 298),
		Vector2(600, 474),
		Vector2(744, 410),
	]
	return lvl


## Builds a level from a seed. The same seed (with the same GENERATOR_VERSION) always gives the same level.
## Placement rules keep every element within the player's jump range (about 100 px high, 170 px far);
## tests/verify_levels.gd checks the result by simulating the player.
static func generate(seed_value: int) -> Level:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lvl := Level.new()
	lvl.seed_value = seed_value

	# Ground: segments separated by pits (gaps the player can jump over).
	var segments: Array[Vector2] = []
	var cur := TILE * rng.randi_range(11, 16)
	segments.append(Vector2(0.0, cur))
	for i in rng.randi_range(0, 2):
		var seg_start := cur + TILE * rng.randi_range(4, 6)
		if seg_start + 128.0 > ARENA.x:
			break
		cur = minf(seg_start + TILE * rng.randi_range(8, 12), ARENA.x)
		segments.append(Vector2(seg_start, cur))
	var last := segments[segments.size() - 1]
	last.y = ARENA.x
	segments[segments.size() - 1] = last

	var pits: Array[Vector2] = []
	for i in range(1, segments.size()):
		pits.append(Vector2(segments[i - 1].y, segments[i].x))
		lvl.solids.append(Rect2(segments[i - 1].x, GROUND_TOP, segments[i - 1].y - segments[i - 1].x, ARENA.y - GROUND_TOP))
	lvl.solids.append(Rect2(last.x, GROUND_TOP, last.y - last.x, ARENA.y - GROUND_TOP))

	# Platforms: short chains, each step at most 64 px up and 48 px across.
	var platforms: Array[Rect2] = []
	var chain_min_x := 96.0
	for chain in rng.randi_range(1, 2):
		var min_tile := int(ceilf(chain_min_x / TILE))
		var x := TILE * (rng.randi_range(min_tile, min_tile + 12) if chain == 0 else rng.randi_range(min_tile, min_tile + 8))
		var top := GROUND_TOP - TILE * rng.randi_range(4, 5)
		var chain_platforms: Array[Rect2] = []
		var prev_right := 0.0
		for k in rng.randi_range(2, 3):
			var w := TILE * rng.randi_range(5, 7)
			if k > 0:
				x = prev_right + TILE * rng.randi_range(1, 3)
				top = clampf(top - TILE * rng.randi_range(-3, 4), 208.0, 480.0)
			if x + w > ARENA.x - 32.0:
				break
			var candidate := Rect2(x, top, w, PLATFORM_THICKNESS)
			if _blocks_pit(candidate, pits):
				break
			chain_platforms.append(candidate)
			prev_right = x + w
		if chain_platforms.is_empty():
			break
		platforms.append_array(chain_platforms)
		chain_min_x = prev_right + 2.0 * TILE
		if chain_min_x > 640.0:
			break

	# Ground spikes first (the level always needs them), kept away from the spawn, segment edges,
	# each other and low platforms, which would cap the jump over them.
	var spikes: Array[Rect2] = []
	var blocks: Array[Rect2] = []
	var occupied: Array[Vector2] = []
	var spike_goal := rng.randi_range(2, 4)
	var block_goal := rng.randi_range(0, 2)
	for attempt in 400:
		if spikes.size() >= spike_goal:
			break
		var seg := segments[rng.randi_range(0, segments.size() - 1)]
		var w := TILE * rng.randi_range(2, 3)
		var lo := maxf(seg.x + 48.0, 112.0)
		var hi := seg.y - 48.0 - w
		if hi <= lo:
			continue
		var bx := _snap(rng.randf_range(lo, hi))
		if _overlaps_any(bx - 64.0, bx + w + 64.0, occupied) or _under_low_platform(bx - 32.0, bx + w + 32.0, platforms):
			continue
		occupied.append(Vector2(bx, bx + w))
		spikes.append(Rect2(bx, GROUND_TOP - TILE, w, TILE))

	# Too few spikes: retry with tighter spacing (the platform margin stays, since it protects the jump).
	for attempt in 300:
		if spikes.size() >= 2:
			break
		var seg := segments[rng.randi_range(0, segments.size() - 1)]
		var w := TILE * rng.randi_range(1, 2)
		var lo := maxf(seg.x + 32.0, 96.0)
		var hi := seg.y - 32.0 - w
		if hi <= lo:
			continue
		var bx := _snap(rng.randf_range(lo, hi))
		if _overlaps_any(bx - 48.0, bx + w + 48.0, occupied) or _under_low_platform(bx - 32.0, bx + w + 32.0, platforms):
			continue
		occupied.append(Vector2(bx, bx + w))
		spikes.append(Rect2(bx, GROUND_TOP - TILE, w, TILE))

	# Spikes on platforms: one tile near the middle, so there is room to land on either side.
	var spiked_platforms := {}
	for attempt in 100:
		if spikes.size() >= spike_goal or platforms.is_empty():
			break
		var idx := rng.randi_range(0, platforms.size() - 1)
		var p := platforms[idx]
		if p.size.x < 80.0 or spiked_platforms.has(idx):
			continue
		spiked_platforms[idx] = true
		var tiles := int(p.size.x / TILE)
		var tile_index := tiles / 2 - (rng.randi_range(0, 1) if tiles >= 6 else 0)
		spikes.append(Rect2(p.position.x + TILE * tile_index, p.position.y - TILE, TILE, TILE))

	# Solid blocks fill whatever ground is left.
	for attempt in 200:
		if blocks.size() >= block_goal:
			break
		var seg := segments[rng.randi_range(0, segments.size() - 1)]
		var w := TILE * rng.randi_range(2, 3)
		var lo := maxf(seg.x + 48.0, 112.0)
		var hi := seg.y - 48.0 - w
		if hi <= lo:
			continue
		var bx := _snap(rng.randf_range(lo, hi))
		if _overlaps_any(bx - 64.0, bx + w + 64.0, occupied) or _under_low_platform(bx - 32.0, bx + w + 32.0, platforms):
			continue
		occupied.append(Vector2(bx, bx + w))
		var h := TILE * rng.randi_range(3, 4)
		blocks.append(Rect2(bx, GROUND_TOP - h, w, h))

	lvl.solids.append_array(platforms)
	lvl.solids.append_array(blocks)
	lvl.traps = spikes

	# Coins: one per platform, one above each pit and ground spike, the rest on the ground.
	var candidates: Array[Vector2] = []
	for i in platforms.size():
		var p := platforms[i]
		var cx := p.position.x + p.size.x / 2.0
		if spiked_platforms.has(i):
			for s in spikes:
				if s.position.y == p.position.y - TILE and s.position.x >= p.position.x and s.end.x <= p.end.x:
					var spike_mid := s.position.x + s.size.x / 2.0
					cx = p.position.x + 16.0 if spike_mid - p.position.x > p.end.x - spike_mid else p.end.x - 16.0
		candidates.append(Vector2(cx, p.position.y - 22.0))
	for pit in pits:
		candidates.append(Vector2((pit.x + pit.y) / 2.0, GROUND_TOP - 70.0))
	for spike in spikes:
		if is_equal_approx(spike.position.y, GROUND_TOP - TILE):   # ground spikes: a coin in the arc of the jump over them
			candidates.append(Vector2(spike.position.x + spike.size.x / 2.0, GROUND_TOP - 70.0))
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var target := rng.randi_range(6, 9)
	for c in candidates:
		if lvl.coins.size() >= target:
			break
		if lvl._coin_fits(c):
			lvl.coins.append(c)
	for attempt in 200:
		if lvl.coins.size() >= target:
			break
		var seg := segments[rng.randi_range(0, segments.size() - 1)]
		var c := Vector2(rng.randf_range(seg.x + 20.0, seg.y - 20.0), GROUND_TOP - 24.0)
		if lvl._coin_fits(c):
			lvl.coins.append(c)
	lvl.coins.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return lvl


## The part of a trap rectangle that actually kills (the visible spikes).
static func trap_hitbox(trap: Rect2) -> Rect2:
	return trap.grow_individual(0.0, -TRAP_INSET, 0.0, 0.0)


static func _snap(value: float) -> float:
	return roundf(value / TILE) * TILE


static func _overlaps_any(from_x: float, to_x: float, ranges: Array[Vector2]) -> bool:
	for r in ranges:
		if from_x < r.y and to_x > r.x:
			return true
	return false


## A low platform over a pit acts as a ceiling for the jump across it, so it is not allowed within 32 px of one.
static func _blocks_pit(p: Rect2, pits: Array[Vector2]) -> bool:
	if p.end.y <= LOW_BOTTOM:
		return false
	for pit in pits:
		if p.position.x < pit.y + 32.0 and p.end.x > pit.x - 32.0:
			return true
	return false


static func _under_low_platform(from_x: float, to_x: float, platforms: Array[Rect2]) -> bool:
	for p in platforms:
		if p.end.y > LOW_BOTTOM and from_x < p.end.x and to_x > p.position.x:
			return true
	return false


## A coin fits when it is clear of every solid and trap and not too close to another coin.
func _coin_fits(c: Vector2) -> bool:
	for r in solids:
		if c.distance_to(c.clamp(r.position, r.end)) < COIN_RADIUS + 10.0:
			return false
	for r in traps:
		if c.distance_to(c.clamp(r.position - Vector2(12, 12), r.end + Vector2(12, 12))) < COIN_RADIUS + 10.0 and \
				c.x > r.position.x - 30.0 and c.x < r.end.x + 30.0:
			return false
	for other in coins:
		if c.distance_to(other) < 40.0:
			return false
	if c.distance_to(START_POS) < 64.0:
		return false   # would be collected the moment the level starts
	return c.x > 20.0 and c.x < ARENA.x - 20.0
