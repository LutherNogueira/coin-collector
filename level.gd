class_name Level
extends RefCounted
## A one-screen level: solid blocks, traps and coins. Level 0 is hand-made; any other seed is generated.

const ARENA := Vector2(800, 600)
const START_POS := Vector2(40, 528)
const GROUND_TOP := 540.0
const COIN_RADIUS := 12.0

var seed_value := 0
var solids: Array[Rect2] = []
var traps: Array[Rect2] = []
var coins: Array[Vector2] = []


static func hand_made() -> Level:
	var lvl := Level.new()
	lvl.solids = [
		Rect2(0, 540, 300, 60),
		Rect2(380, 540, 180, 60),
		Rect2(640, 540, 160, 60),
		Rect2(440, 480, 40, 60),
		Rect2(170, 450, 110, 16),
		Rect2(330, 370, 110, 16),
		Rect2(520, 300, 100, 16),
		Rect2(670, 420, 120, 16),
	]
	lvl.traps = [
		Rect2(100, 524, 40, 16),
		Rect2(500, 524, 40, 16),
		Rect2(715, 404, 30, 16),
	]
	lvl.coins = [
		Vector2(120, 470),
		Vector2(225, 428),
		Vector2(340, 470),
		Vector2(385, 348),
		Vector2(570, 278),
		Vector2(600, 470),
		Vector2(768, 398),
	]
	return lvl


## Builds a level from a seed. The same seed always gives the same level.
## Placement rules keep every element within the player's jump range (about 100 px high, 170 px far);
## tests/verify_levels.gd checks the result by simulating the player.
static func generate(seed_value: int) -> Level:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lvl := Level.new()
	lvl.seed_value = seed_value

	# Ground: segments separated by pits (gaps the player can jump over).
	var segments: Array[Vector2] = []
	var cur := rng.randf_range(180.0, 260.0)
	segments.append(Vector2(0.0, cur))
	for i in rng.randi_range(0, 2):
		var seg_start := cur + rng.randf_range(60.0, 100.0)
		if seg_start + 120.0 > ARENA.x:
			break
		cur = minf(seg_start + rng.randf_range(120.0, 200.0), ARENA.x)
		segments.append(Vector2(seg_start, cur))
	var last := segments[segments.size() - 1]
	last.y = ARENA.x
	segments[segments.size() - 1] = last

	var pits: Array[Vector2] = []
	for i in range(1, segments.size()):
		pits.append(Vector2(segments[i - 1].y, segments[i].x))
		lvl.solids.append(Rect2(segments[i - 1].x, GROUND_TOP, segments[i - 1].y - segments[i - 1].x, ARENA.y - GROUND_TOP))
	lvl.solids.append(Rect2(last.x, GROUND_TOP, last.y - last.x, ARENA.y - GROUND_TOP))

	# Platforms: short chains, each step at most 70 px up and 60 px across.
	var platforms: Array[Rect2] = []
	var chain_min_x := 100.0
	for chain in rng.randi_range(1, 2):
		var x := rng.randf_range(chain_min_x, chain_min_x + 200.0) if chain == 0 else rng.randf_range(chain_min_x, chain_min_x + 120.0)
		var top := GROUND_TOP - rng.randf_range(60.0, 80.0)
		var chain_platforms: Array[Rect2] = []
		var prev_right := 0.0
		for k in rng.randi_range(2, 3):
			var w := rng.randf_range(80.0, 120.0)
			if k > 0:
				x = prev_right + rng.randf_range(20.0, 60.0)
				top = clampf(top - rng.randf_range(-50.0, 70.0), 200.0, 480.0)
			if x + w > ARENA.x - 30.0:
				break
			var candidate := Rect2(x, top, w, 16.0)
			if _blocks_pit(candidate, pits):
				break
			chain_platforms.append(candidate)
			prev_right = x + w
		if chain_platforms.is_empty():
			break
		platforms.append_array(chain_platforms)
		chain_min_x = prev_right + 40.0
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
		var w := rng.randf_range(30.0, 50.0)
		var lo := maxf(seg.x + 50.0, 110.0)
		var hi := seg.y - 50.0 - w
		if hi <= lo:
			continue
		var bx := rng.randf_range(lo, hi)
		if _overlaps_any(bx - 60.0, bx + w + 60.0, occupied) or _under_low_platform(bx - 30.0, bx + w + 30.0, platforms):
			continue
		occupied.append(Vector2(bx, bx + w))
		spikes.append(Rect2(bx, GROUND_TOP - 16.0, w, 16.0))

	# Too few spikes: retry with tighter spacing (the platform margin stays, since it protects the jump).
	for attempt in 300:
		if spikes.size() >= 2:
			break
		var seg := segments[rng.randi_range(0, segments.size() - 1)]
		var w := rng.randf_range(26.0, 40.0)
		var lo := maxf(seg.x + 40.0, 100.0)
		var hi := seg.y - 40.0 - w
		if hi <= lo:
			continue
		var bx := rng.randf_range(lo, hi)
		if _overlaps_any(bx - 40.0, bx + w + 40.0, occupied) or _under_low_platform(bx - 30.0, bx + w + 30.0, platforms):
			continue
		occupied.append(Vector2(bx, bx + w))
		spikes.append(Rect2(bx, GROUND_TOP - 16.0, w, 16.0))

	# Spikes on platforms (centered, so there is room to land on either side and jump over).
	var spiked_platforms := {}
	for attempt in 100:
		if spikes.size() >= spike_goal or platforms.is_empty():
			break
		var idx := rng.randi_range(0, platforms.size() - 1)
		var p := platforms[idx]
		if p.size.x < 80.0 or spiked_platforms.has(idx):
			continue
		spiked_platforms[idx] = true
		var spike_w := 24.0 if p.size.x >= 110.0 else 20.0
		var jitter := rng.randf_range(-6.0, 6.0)
		spikes.append(Rect2(p.position.x + p.size.x / 2.0 - spike_w / 2.0 + jitter, p.position.y - 16.0, spike_w, 16.0))

	# Solid blocks fill whatever ground is left.
	for attempt in 200:
		if blocks.size() >= block_goal:
			break
		var seg := segments[rng.randi_range(0, segments.size() - 1)]
		var w := rng.randf_range(30.0, 50.0)
		var lo := maxf(seg.x + 50.0, 110.0)
		var hi := seg.y - 50.0 - w
		if hi <= lo:
			continue
		var bx := rng.randf_range(lo, hi)
		if _overlaps_any(bx - 60.0, bx + w + 60.0, occupied) or _under_low_platform(bx - 30.0, bx + w + 30.0, platforms):
			continue
		occupied.append(Vector2(bx, bx + w))
		var h := rng.randf_range(40.0, 70.0)
		blocks.append(Rect2(bx, GROUND_TOP - h, w, h))

	lvl.solids.append_array(platforms)
	lvl.solids.append_array(blocks)
	lvl.traps = spikes

	# Coins: one per platform, one above each pit, the rest on the ground.
	var candidates: Array[Vector2] = []
	for i in platforms.size():
		var p := platforms[i]
		var cx := p.position.x + p.size.x / 2.0
		if spiked_platforms.has(i):
			for s in spikes:
				if s.position.y == p.position.y - 16.0 and s.position.x >= p.position.x and s.end.x <= p.end.x:
					cx = p.position.x + 16.0 if (s.position.x + 12.0) - p.position.x > p.end.x - (s.position.x + 12.0) else p.end.x - 16.0
		candidates.append(Vector2(cx, p.position.y - 22.0))
	for pit in pits:
		candidates.append(Vector2((pit.x + pit.y) / 2.0, 470.0))
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


static func _overlaps_any(from_x: float, to_x: float, ranges: Array[Vector2]) -> bool:
	for r in ranges:
		if from_x < r.y and to_x > r.x:
			return true
	return false


## A low platform over a pit acts as a ceiling for the jump across it, so it is not allowed within 30 px of one.
static func _blocks_pit(p: Rect2, pits: Array[Vector2]) -> bool:
	if p.end.y <= 440.0:
		return false
	for pit in pits:
		if p.position.x < pit.y + 30.0 and p.end.x > pit.x - 30.0:
			return true
	return false


static func _under_low_platform(from_x: float, to_x: float, platforms: Array[Rect2]) -> bool:
	for p in platforms:
		if p.end.y > 440.0 and from_x < p.end.x and to_x > p.position.x:
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
	return c.x > 20.0 and c.x < ARENA.x - 20.0
