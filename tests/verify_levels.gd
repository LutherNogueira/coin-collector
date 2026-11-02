extends SceneTree
## Checks that levels are well formed and completable.
##
## For each seed it runs structural checks, then explores what the player can reach by simulating real
## physics: walking, and jumping with direction changes mid-air. A coin counts only when touched on a path
## that ends alive (dying restores every coin). A level passes when every coin is touched.
##
## Usage: godot --headless --path . --script res://tests/verify_levels.gd -- [--from=S] [--seeds=N]
## Checks seeds S..S+N (default 0..30). Seed 0 is the hand-made level; any other seed is generated.

const FRAME := 1.0 / 60.0
const STATE_GRID := 12.0
const JUMP_SWITCH_TIMES := [0.25, 0.5]
const DIRECTIONS := [-1.0, 0.0, 1.0]


func _init() -> void:
	var first_seed := 0
	var seed_count := 30
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seed_count = int(arg.get_slice("=", 1))
		elif arg.begins_with("--from="):
			first_seed = int(arg.get_slice("=", 1))

	var failed := 0
	for seed_value in range(first_seed, first_seed + seed_count + 1):
		var level := Level.hand_made() if seed_value == 0 else Level.generate(seed_value)
		var problems := _structure_problems(level)
		var unreachable := _unreachable_coins(level)
		for i in unreachable:
			problems.append("coin %d at %s is unreachable" % [i, level.coins[i]])
		if problems.is_empty():
			print("seed %d: ok (%d coins, %d traps)" % [seed_value, level.coins.size(), level.traps.size()])
		else:
			failed += 1
			print("seed %d: FAILED" % seed_value)
			for p in problems:
				print("  - ", p)
	print("%d of %d levels failed" % [failed, seed_count + 1])
	quit(1 if failed > 0 else 0)


func _structure_problems(level: Level) -> Array[String]:
	var problems: Array[String] = []
	if level.coins.size() < 6 or level.coins.size() > 9:
		problems.append("%d coins, expected 6-9" % level.coins.size())
	if level.traps.size() < 2 or level.traps.size() > 4:
		problems.append("%d traps, expected 2-4" % level.traps.size())

	var bounds := Rect2(Vector2.ZERO, Level.ARENA)
	for i in level.solids.size():
		if not bounds.encloses(level.solids[i]):
			problems.append("solid %s leaves the arena" % level.solids[i])
		for j in range(i + 1, level.solids.size()):
			if level.solids[i].intersects(level.solids[j]):
				problems.append("solids overlap: %s and %s" % [level.solids[i], level.solids[j]])
	for trap in level.traps:
		for s in level.solids:
			if trap.intersects(s):
				problems.append("trap %s overlaps solid %s" % [trap, s])
	for c in level.coins:
		for r in level.solids + level.traps:
			if c.distance_to(c.clamp(r.position, r.end)) < Level.COIN_RADIUS:
				problems.append("coin %s overlaps %s" % [c, r])
	for r in level.solids + level.traps:
		var bottom_ok := _on_grid(r.end.y) or is_equal_approx(r.end.y, Level.ARENA.y)   # the ground runs off the bottom
		if not (_on_grid(r.position.x) and _on_grid(r.position.y) and _on_grid(r.size.x) and bottom_ok):
			problems.append("%s is off the 16 px grid" % r)
	var start := PlatformPhysics.Body.new(Level.START_POS)
	for r in level.solids + level.traps:
		if start.rect().intersects(r):
			problems.append("start position overlaps %s" % r)
	return problems


func _on_grid(value: float) -> bool:
	return is_zero_approx(fposmod(value, Level.TILE))


## Returns the indices of coins the simulated player cannot touch.
func _unreachable_coins(level: Level) -> Array[int]:
	var touched := {}
	var seen := {}
	var queue: Array[Vector2] = []
	_enqueue(Level.START_POS, seen, queue)

	var head := 0
	while head < queue.size():
		var pos := queue[head]
		head += 1
		for dir in [-1.0, 1.0]:
			_walk(level, pos, dir, touched, seen, queue)
		for first in DIRECTIONS:
			for second in DIRECTIONS:
				if first == second:
					_jump(level, pos, first, second, 0.0, touched, seen, queue)
				else:
					for switch_time in JUMP_SWITCH_TIMES:
						_jump(level, pos, first, second, switch_time, touched, seen, queue)

	var missing: Array[int] = []
	for i in level.coins.size():
		if not touched.has(i):
			missing.append(i)
	return missing


func _enqueue(pos: Vector2, seen: Dictionary, queue: Array[Vector2]) -> void:
	var key := Vector2i(roundi(pos.x / STATE_GRID), roundi(pos.y))
	if not seen.has(key):
		seen[key] = true
		queue.append(pos)


func _walk(level: Level, from: Vector2, dir: float, touched: Dictionary, seen: Dictionary, queue: Array[Vector2]) -> void:
	var body := PlatformPhysics.Body.new(from)
	var pending := {}
	var stuck := 0
	for tick in 600:
		var before := body.pos
		if not _advance(level, body, dir, false, pending):
			return
		touched.merge(pending)
		if body.on_floor:
			_enqueue(body.pos, seen, queue)
		stuck = stuck + 1 if body.pos.is_equal_approx(before) else 0
		if stuck > 3:
			return


func _jump(level: Level, from: Vector2, first: float, second: float, switch_time: float, touched: Dictionary, seen: Dictionary, queue: Array[Vector2]) -> void:
	var body := PlatformPhysics.Body.new(from)
	var pending := {}
	var jump := true
	for tick in 240:
		var dir := first if tick * FRAME < switch_time else second
		if not _advance(level, body, dir, jump, pending):
			return
		jump = false
		if body.on_floor:
			touched.merge(pending)
			_enqueue(body.pos, seen, queue)
			return


## One 60 fps frame (two substeps). Returns false when the player dies. Coins touched are added to `touched`;
## callers only keep them if the player survives, because dying restores every coin.
func _advance(level: Level, body: PlatformPhysics.Body, dir: float, jump: bool, touched: Dictionary) -> bool:
	var jump_now := jump
	for i in 2:
		PlatformPhysics.step(body, level, PlatformPhysics.SUBSTEP, dir, jump_now)
		jump_now = false
		for c in level.coins.size():
			if PlatformPhysics.circle_hits(body, level.coins[c], Level.COIN_RADIUS):
				touched[c] = true
		if PlatformPhysics.death_cause(body, level) != "":
			return false
	return true
