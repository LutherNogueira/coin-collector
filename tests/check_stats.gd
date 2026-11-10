extends SceneTree
## Checks the statistics screen inside the game: the numbers on screen are the gold numbers from the pipeline,
## Esc steps back one level at a time (statistics, then menu), and a build without data says so instead of crashing.
##
## Needs stats/data/gold.json, which the pipeline writes:
##   python -m pipeline.run_pipeline --raw <events> --out stats/data/gold.json
## Usage: godot --headless --path . --script res://tests/check_stats.gd

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
	for i in 3:
		await process_frame


func _init() -> void:
	var gold := MetricsData.load_file(StatsScreen.data_path)
	_expect(gold.ok, "stats/data/gold.json loads (%s)" % gold.error)
	if not gold.ok:
		quit(1)
		return

	Settings.path = "user://stats_test_settings.cfg"
	main = load("res://main.tscn").instantiate()
	main.logger.log_path = "user://stats_test_events.jsonl"
	root.add_child(main)
	await process_frame

	# Esc, then the Statistics button, open the screen over the paused game.
	await _press_escape()
	main.menu.open_statistics()
	await process_frame
	var stats: StatsScreen = main.menu.stats
	_expect(stats.is_open() and main.menu.is_open() and paused, "Statistics opens over the menu, with the game still paused")

	# The numbers on screen are the gold numbers.
	var s := gold.summary
	_expect(stats.kpi_value["rounds"].text == MetricsData.format_int(s["rounds"]), "rounds card shows %s" % MetricsData.format_int(s["rounds"]))
	_expect(stats.kpi_value["completion"].text == MetricsData.percent(s["completion_rate"]), "completion card shows %s" % MetricsData.percent(s["completion_rate"]))
	_expect(stats.kpi_value["duration"].text == MetricsData.seconds(s["avg_duration_completed_s"]), "average time card shows %s" % MetricsData.seconds(s["avg_duration_completed_s"]))
	_expect(stats.kpi_value["death_rate"].text == MetricsData.percent(s["death_rate"]), "death rate card shows %s" % MetricsData.percent(s["death_rate"]))
	_expect(stats.kpi_caption["death_rate"].text == "%s / %s attempts" % [MetricsData.format_int(s["deaths"]), MetricsData.format_int(s["attempts"])],
			"death rate caption reads X / Y attempts")
	_expect(stats.rounds_chart.values.size() == gold.daily.size(), "the rounds chart has one bar per day (%d)" % gold.daily.size())
	_expect(stats.death_chart.values.size() == gold.daily.size(), "the death rate chart has one point per day")
	var total_rounds := 0.0
	for value in stats.rounds_chart.values:
		total_rounds += value
	_expect(int(total_rounds) == int(s["rounds"]), "the bars add up to the total number of rounds")
	_expect(stats.badge.text.contains("SYNTHETIC") == gold.is_synthetic(), "the badge says whether the data is synthetic")
	var few: bool = int(s.get("sessions", 0)) < StatsScreen.FEW_SESSIONS
	_expect(stats.badge.text.contains("early data") == (few and not gold.is_synthetic()), "the badge warns when real data comes from only a few sessions")

	# Esc steps back one level at a time.
	await _press_escape()
	_expect(not stats.is_open() and main.menu.is_open() and paused, "Esc closes the statistics and leaves the menu open")
	await _press_escape()
	_expect(not main.menu.is_open() and not paused, "a second Esc closes the menu and resumes the game")

	# The statistics follow the chosen character, and the screen can be opened again.
	main.menu.open()
	main.menu.set_avatar("pink_man", true)
	main.menu.open_statistics()
	await process_frame
	_expect(stats.is_open() and stats.kpi_value.has("rounds"), "the screen can be opened again after a character change")
	stats.close()
	main.menu.close()

	# Without data, the screen explains what to do instead of crashing.
	var real_path := StatsScreen.data_path
	StatsScreen.data_path = "res://stats/data/does_not_exist.json"
	stats.open()
	await process_frame
	_expect(stats.is_open() and stats.message != null and stats.kpi_value.is_empty(), "a build without data shows a message, not a crash")
	stats.close()
	StatsScreen.data_path = real_path

	# Formatting helpers.
	_expect(MetricsData.format_int(141093.0) == "141,093" and MetricsData.format_int(7.0) == "7" and MetricsData.format_int(1000.0) == "1,000", "thousands separators")
	_expect(MetricsData.percent(0.6739) == "67.4%" and MetricsData.percent(null) == "-", "percent formatting")

	paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
