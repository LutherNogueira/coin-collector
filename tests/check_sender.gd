extends SceneTree
## Checks the event sink and the privacy switch. The JavaScript batching only exists in the browser, so it is
## checked by playing the web export; here we check what the desktop build can: the logger feeds its sink with
## the exact lines it writes, the menu shows the privacy switch only where something is sent, and the choice sticks.
##
## Usage: godot --headless --path . --script res://tests/check_sender.gd

var failures := 0
var received: Array[String] = []


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	Settings.path = "user://sender_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	var log_path := "user://sender_test_events.jsonl"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(log_path))

	var logger := EventLogger.new()
	logger.log_path = log_path
	logger.sink = func(line: String) -> void: received.append(line)
	logger.log_event("session_start")
	logger.new_round()
	logger.log_event("player_jump", {"t": 1.0, "x": 10.0, "y": 20.0})
	_expect(received.size() == 2, "the sink gets every event")
	var file := FileAccess.open(log_path, FileAccess.READ)
	var written := file.get_as_text().strip_edges().split("\n")
	_expect(written.size() == 2 and written[0] == received[0] and written[1] == received[1], "the sink gets exactly the lines written to the file")
	var event: Dictionary = JSON.parse_string(received[1])
	_expect(event.evento == "player_jump" and event.schema_version == EventLogger.SCHEMA_VERSION, "a sunk line is a complete event")

	var plain := EventLogger.new()   # no sink: logging still works
	plain.log_path = log_path
	plain.log_event("session_end")
	_expect(received.size() == 2, "without a sink nothing is forwarded")

	# The privacy choice: on by default, saved when switched, and the notice is shown once.
	_expect(Settings.load_telemetry(), "sending is on by default")
	Settings.save_telemetry(false)
	_expect(not Settings.load_telemetry(), "switching it off is remembered")
	Settings.save_telemetry(true)
	_expect(Settings.load_telemetry(), "switching it back on is remembered")
	_expect(not Settings.notice_seen(), "the first visit has not seen the notice")
	Settings.mark_notice_seen()
	_expect(Settings.notice_seen(), "the notice is not shown again once seen")
	_expect(Settings.load_telemetry(), "marking the notice keeps the other settings")

	# On desktop nothing is sent, so the sender does nothing and the menu has no switch.
	_expect(not EventSender.is_available(), "the desktop build does not send")
	var sender := EventSender.new()
	sender.start(true)
	sender.push("{}")   # must not crash without a browser
	var game: Node = load("res://main.tscn").instantiate()
	game.logger.log_path = "user://sender_test_events.jsonl"
	root.add_child(game)
	await process_frame
	_expect(game.menu._privacy_button == null, "the desktop menu has no privacy switch")
	_expect(game.notice_left == 0.0, "the desktop build shows no notice")
	game.queue_free()
	await process_frame

	for p in [Settings.path, log_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
