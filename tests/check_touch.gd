extends SceneTree
## Checks the touch controls: the floating analog stick, the jump zone, the menu button, that fingers do not get in
## each other's way, and that the game reads all of it (including the sound switch in the menu).
##
## Usage: godot --headless --path . --script res://tests/check_touch.gd

var failures := 0
var taps := 0
var menu_taps := 0
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


func _screen() -> Vector2:
	return target.get_viewport().get_visible_rect().size


func _left_thumb() -> Vector2:
	return Vector2(_screen().x * 0.25, _screen().y * 0.7)


func _right_thumb() -> Vector2:
	return Vector2(_screen().x * 0.75, _screen().y * 0.7)


func _init() -> void:
	# Without a touch screen the controls stay hidden and do nothing.
	var hidden := TouchControls.new()
	target = hidden
	root.add_child(hidden)
	await process_frame
	_expect(not hidden.is_active() and not hidden.visible, "no touch screen: the controls are hidden")
	await _touch(0, _left_thumb(), true)
	await _drag(0, _left_thumb() + Vector2(60, 0))
	_expect(hidden.move_x() == 0.0 and not hidden.stick_active(), "hidden controls ignore touches")
	hidden.queue_free()

	var controls := TouchControls.new()
	controls.forced = true
	target = controls
	controls.pressed.connect(func(_p: Vector2) -> void: taps += 1)
	controls.menu_requested.connect(func() -> void: menu_taps += 1)
	root.add_child(controls)
	await process_frame
	_expect(controls.visible, "forced: the controls are visible")

	# The stick floats: it starts wherever the left thumb lands, and pushes by how far the thumb moves from there.
	var start := _left_thumb()
	await _touch(0, start, true)
	_expect(controls.stick_active() and controls.move_x() == 0.0, "a thumb on the left half starts the stick, standing still")
	await _drag(0, start + Vector2(4, 0))
	_expect(controls.move_x() == 0.0, "a tiny movement stays inside the dead zone")
	await _drag(0, start + Vector2(TouchControls.STICK_RADIUS * 0.5, 0))
	_expect(absf(controls.move_x() - 0.4118) < 0.01, "half way out is a gentle push (%.3f)" % controls.move_x())
	await _drag(0, start + Vector2(TouchControls.STICK_RADIUS * 3.0, 0))
	_expect(controls.move_x() == 1.0, "pulled beyond the edge it is full speed right")
	await _drag(0, start + Vector2(-TouchControls.STICK_RADIUS * 3.0, 40))
	_expect(controls.move_x() == -1.0, "pulled left it is full speed left, and up or down makes no difference")
	await _touch(0, start, false)
	_expect(controls.move_x() == 0.0 and not controls.stick_active(), "lifting the thumb stops")

	# Jump and stick at the same time, each on its own finger.
	await _touch(0, start, true)
	await _drag(0, start + Vector2(TouchControls.STICK_RADIUS, 0))
	await _touch(1, _right_thumb(), true)
	_expect(controls.jump_down() and controls.move_x() == 1.0, "the right thumb jumps while the left keeps moving")
	await _touch(1, _right_thumb(), false)
	_expect(not controls.jump_down() and controls.move_x() == 1.0, "lifting the jump leaves the movement alone")
	await _touch(2, _left_thumb() + Vector2(0, 30), true)
	_expect(controls.move_x() == 1.0 and not controls.jump_down(), "a second finger on the left half does not take over the stick")
	await _touch(2, Vector2.ZERO, false)
	await _touch(0, start, false)

	# The menu button is not a jump and not a tap for the "next level" gesture.
	var taps_before := taps
	await _touch(3, controls.menu_rect().get_center(), true)
	_expect(menu_taps == 1 and not controls.jump_down() and taps == taps_before, "the menu button asks for the menu, without jumping")
	await _touch(3, Vector2.ZERO, false)
	_expect(menu_taps == 1, "and only once per press")

	await _touch(4, _right_thumb(), true)
	_expect(controls.jump_down() and taps == taps_before + 1, "other presses are announced")
	controls.release_all()
	_expect(not controls.jump_down(), "release_all lets go of everything")
	controls.queue_free()
	await process_frame

	# The game reads the controls.
	var was_muted := Sfx.is_muted()
	var game: Node = load("res://main.tscn").instantiate()
	game.logger.log_path = "user://touch_test_events.jsonl"
	game.touch.forced = true
	root.add_child(game)
	await process_frame
	target = game.touch
	var origin := _left_thumb()
	await _touch(0, origin, true)
	await _drag(0, origin + Vector2(TouchControls.STICK_RADIUS, 0))
	_expect(game._read_move_x() == 1.0, "the game moves right while the stick is pushed right")
	await _drag(0, origin + Vector2(TouchControls.STICK_RADIUS * 0.5, 0))
	_expect(game._read_move_x() > 0.0 and game._read_move_x() < 1.0, "and slower on a gentle push")
	await _touch(0, origin, false)
	_expect(game._read_move_x() == 0.0, "and stops when the thumb lifts")

	# The menu button opens the menu, which pauses the game and lets go of the held stick.
	await _touch(0, origin, true)
	await _drag(0, origin + Vector2(TouchControls.STICK_RADIUS, 0))
	await _touch(1, target.menu_rect().get_center(), true)
	await _frames(3)
	_expect(game.menu.is_open() and paused, "the menu button opens the menu and pauses the game")
	_expect(not game.touch.stick_active(), "opening the menu lets go of the stick")
	await _touch(1, Vector2.ZERO, false)

	# The sound switch lives in the menu.
	game.menu.toggle_sound()
	_expect(Sfx.is_muted() != was_muted, "the menu's sound button mutes (or unmutes)")
	game.menu.toggle_sound()
	_expect(Sfx.is_muted() == was_muted, "and switches back")
	game.menu.close()
	_expect(not paused, "closing the menu resumes the game")

	# A tap anywhere after a win starts the next level.
	var rounds_before: int = game.rounds_started
	game.state = game.State.ENDED
	await _touch(5, _right_thumb(), true)
	await _touch(5, _right_thumb(), false)
	_expect(game.rounds_started == rounds_before + 1 and game.state == game.State.PLAYING, "a tap after a win starts the next level")
	game.queue_free()
	await process_frame

	paused = false
	Sfx.set_muted(was_muted)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://touch_test_events.jsonl"))
	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
