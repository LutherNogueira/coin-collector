extends SceneTree
## Checks the on-screen touch buttons: each finger is tracked on its own, sliding between buttons changes the
## direction, a jump button press gives one jump, and a tap after a win starts the next level.
##
## Usage: godot --headless --path . --script res://tests/check_touch.gd

var failures := 0
var tap_count := 0
## Events go straight to this node: the headless window is 64x64, which would rescale parsed positions.
var target: TouchControls


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _frames(count: int = 2) -> void:
	for i in count:
		await process_frame


func _touch(index: int, pos: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = down
	target._input(event)
	await _frames()


func _drag(index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	target._input(event)
	await _frames()


func _center(button: String) -> Vector2:
	return target.button_rect(button).get_center()


func _init() -> void:
	# Without a touch screen the buttons stay hidden and do nothing.
	var hidden := TouchControls.new()
	target = hidden
	root.add_child(hidden)
	await process_frame
	_expect(not hidden.is_active() and not hidden.visible, "no touch screen: the buttons are hidden")
	await _touch(0, _center("left"), true)
	_expect(hidden.move_x() == 0.0, "hidden buttons ignore touches")
	hidden.queue_free()

	var controls := TouchControls.new()
	controls.forced = true
	target = controls
	controls.pressed.connect(func(_p: Vector2) -> void: tap_count += 1)
	root.add_child(controls)
	await process_frame
	_expect(controls.visible, "forced: the buttons are visible")

	await _touch(0, _center("left"), true)
	_expect(controls.move_x() == -1.0 and controls.is_held("left"), "holding left moves left")
	await _touch(0, _center("left"), false)
	_expect(controls.move_x() == 0.0, "lifting the finger stops")

	await _touch(0, _center("right"), true)
	_expect(controls.move_x() == 1.0, "holding right moves right")
	await _touch(1, _center("jump"), true)
	_expect(controls.move_x() == 1.0 and controls.jump_down(), "a second finger jumps while the first keeps moving")
	await _touch(1, _center("jump"), false)
	_expect(not controls.jump_down() and controls.move_x() == 1.0, "lifting the jump finger leaves the movement alone")

	await _drag(0, _center("left"))
	_expect(controls.move_x() == -1.0, "sliding from right to left changes direction")
	await _drag(0, Vector2(400, 200))
	_expect(controls.move_x() == 0.0, "sliding off the buttons stops")
	await _touch(0, Vector2(400, 200), false)

	await _touch(2, _center("left") + Vector2(-10, 8), true)
	_expect(controls.is_held("left"), "a press just outside a button still counts")
	await _touch(3, _center("right"), true)
	_expect(controls.move_x() == 0.0, "left and right together cancel out")
	await _touch(2, Vector2.ZERO, false)
	await _touch(3, Vector2.ZERO, false)
	_expect(tap_count > 0, "every press is announced")

	# The game reads the buttons: movement, one jump per press, and a tap after a win starts a new level.
	controls.queue_free()
	await process_frame
	var game: Node = load("res://main.tscn").instantiate()
	game.logger.log_path = "user://touch_test_events.jsonl"
	game.touch.forced = true
	root.add_child(game)
	await process_frame
	target = game.touch
	await _touch(0, _center("right"), true)
	_expect(game._read_move_x() == 1.0, "the game moves right while the right button is held")
	await _touch(0, _center("right"), false)
	_expect(game._read_move_x() == 0.0, "and stops when it is released")
	var rounds_before: int = game.rounds_started
	game.state = game.State.ENDED
	await _touch(0, Vector2(400, 300), true)
	await _touch(0, Vector2(400, 300), false)
	_expect(game.rounds_started == rounds_before + 1 and game.state == game.State.PLAYING, "a tap after a win starts the next level")
	game.queue_free()
	await process_frame

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://touch_test_events.jsonl"))
	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
