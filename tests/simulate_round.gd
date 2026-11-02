extends SceneTree
## Drives the game headlessly through scripted and random play, writing a real events.jsonl,
## then run validate_events.py on it. It writes to its own file, so it never touches a log from real play.
##
## Usage: godot --headless --path . --script res://tests/simulate_round.gd
## Then:  python validate_events.py <user data folder>/simulated_events.jsonl
##         (on Windows: %APPDATA%/Godot/app_userdata/Coin Collector/)

var main: Node
var overlaps := 0
var failures := 0


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _run(seconds: float, move_x: float, jump_every: int = 0) -> void:
	for i in int(seconds * 60.0):
		main._step(1.0 / 60.0, move_x, jump_every > 0 and i % jump_every == 0)
		for s: Rect2 in main.level.solids:
			if main.body.rect().grow(-0.01).intersects(s):
				overlaps += 1


func _teleport(pos: Vector2, airborne: bool = false) -> void:
	main.body.pos = pos
	main.body.vel = Vector2.ZERO
	main.body.on_floor = not airborne


const SIM_LOG := "user://simulated_events.jsonl"


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SIM_LOG))
	main = load("res://main.tscn").instantiate()
	main.logger.log_path = SIM_LOG   # set before _ready logs session_start
	root.add_child(main)
	await process_frame   # _ready runs here
	seed(42)

	_expect(main.level.seed_value == 0, "first round plays the hand-made level (seed 0)")

	_run(0.3, 1.0)
	_expect(main.deaths == 1 and main.body.pos.x < 100.0, "walking right hits the first trap and respawns at the start")

	_teleport(Vector2(420, 528))
	_run(1.0, 1.0)
	_expect(is_equal_approx(main.body.pos.x, 428.0), "a solid block stops the player (x=%.1f)" % main.body.pos.x)

	var deaths_before: int = main.deaths
	_teleport(Vector2(340, 500), true)
	_run(2.0, 0.0)
	_expect(main.deaths == deaths_before + 1, "falling into a pit kills")

	for block in 80:
		_run(0.5, [-1.0, 0.0, 1.0][randi() % 3], [0, 20, 35][randi() % 3])
	_expect(overlaps == 0, "random play never puts the player inside a solid (%d overlaps)" % overlaps)

	main._start_round()   # abandons the open round; it must still be closed in the log
	_expect(main.level.seed_value != 0, "second round plays a generated level (seed %d)" % main.level.seed_value)
	for c: Vector2 in main.level.coins:
		_teleport(c)
		main._step(1.0 / 60.0, 0.0, false)
	_expect(main.state == main.State.ENDED and main.completed, "collecting every coin completes the round")

	main._start_round()
	_run(0.5, 0.0)
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_expect(main.state == main.State.ENDED and not main.completed, "closing mid-round ends it as not completed")

	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
