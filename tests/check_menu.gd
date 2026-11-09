extends SceneTree
## Checks the Esc menu: it pauses the game, the choice of character works and is remembered, and closing resumes play.
## Uses its own settings and log files, so it never touches your real ones.
##
## Usage: godot --headless --path . --script res://tests/check_menu.gd

var main: Node
var failures := 0


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(3)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _start_game() -> Node:
	var game: Node = load("res://main.tscn").instantiate()
	game.logger.log_path = "user://menu_test_events.jsonl"
	root.add_child(game)
	await process_frame
	return game


func _init() -> void:
	Settings.path = "user://menu_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://menu_test_events.jsonl"))

	main = await _start_game()
	_expect(main.view.avatar == Avatars.DEFAULT, "the first visit starts with the default character")
	_expect(not main.menu.is_open() and not paused, "the menu starts closed and the game is running")

	# Esc opens the menu and pauses everything that is not the menu or the music.
	await _press_escape()
	_expect(main.menu.is_open() and paused, "Esc opens the menu and pauses the game")
	var clock: float = main.t
	await _frames(30)
	_expect(is_equal_approx(main.t, clock), "the round clock is frozen while the menu is open")
	var music: AudioStreamPlayer = main.get_children().filter(func(n: Node) -> bool: return n is Music)[0]
	_expect(music.playing, "the music keeps playing while paused")

	# Choosing a character.
	main.menu.cycle_avatar(1)
	_expect(main.menu.avatar == "mask_dude" and main.view.avatar == "mask_dude", "choosing the next character changes the player's look")
	_expect(Settings.load_avatar() == "mask_dude", "the choice is saved")
	main.menu.cycle_avatar(-1)
	_expect(main.view.avatar == "ninja_frog", "choosing the previous character goes back")
	main.menu.cycle_avatar(2)   # leave it on a non-default one to check it is remembered
	_expect(main.view.avatar == "pink_man", "two steps forward lands on the third character")
	_expect(Avatars.shifted("virtual_guy", 1) == "ninja_frog" and Avatars.shifted("ninja_frog", -1) == "virtual_guy",
			"the list wraps around at both ends")

	# Esc closes it and the game carries on.
	await _press_escape()
	_expect(not main.menu.is_open() and not paused, "Esc again closes the menu and resumes the game")
	await _frames(20)
	_expect(main.t > clock, "the round clock runs again after closing")

	# A new visit remembers the choice, and stale saved values fall back to the default.
	main.queue_free()
	await process_frame
	main = await _start_game()
	_expect(main.view.avatar == "pink_man" and main.menu.avatar == "pink_man", "the next visit starts with the saved character")
	var stale := ConfigFile.new()
	stale.set_value("player", "avatar", "does_not_exist")
	stale.save(Settings.path)
	_expect(Settings.load_avatar() == Avatars.DEFAULT, "an unknown saved character falls back to the default")

	# Every character has the five animations with the expected number of frames.
	for id in Avatars.ids():
		var frames := PlayerView.frames_for(id)
		var counts := {}
		for anim in PlayerView.ANIMATIONS:
			counts[anim] = frames.get_frame_count(anim)
		_expect(counts == {"idle": 11, "run": 12, "jump": 1, "fall": 1, "hit": 7}, "%s has all its animations %s" % [id, counts])

	# The statistics button points at a page next to the game on the web, and at the published site elsewhere.
	_expect(PauseMenu.STATS_URL_WEB == "metrics/" and PauseMenu.STATS_URL_NATIVE.ends_with("/metrics/"), "the statistics links point at /metrics/")

	paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
