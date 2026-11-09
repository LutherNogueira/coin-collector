extends SceneTree
## Loads the metrics screen with the exported gold data and checks that the numbers on screen are the gold numbers.
##
## Usage (after the pipeline wrote data/gold.json):
##   godot --headless --path metrics_app --script res://tests/check_ui.gd

var failures := 0


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	var data := MetricsData.load_file("res://data/gold.json")
	_expect(data.ok, "data/gold.json loads (%s)" % data.error)
	if not data.ok:
		quit(1)
		return
	var main: Control = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var s := data.summary
	_expect(main.kpi_value["rounds"].text == MetricsData.format_int(s["rounds"]), "rounds card shows %s" % MetricsData.format_int(s["rounds"]))
	_expect(main.kpi_value["completion"].text == MetricsData.percent(s["completion_rate"]), "completion card shows %s" % MetricsData.percent(s["completion_rate"]))
	_expect(main.kpi_value["duration"].text == MetricsData.seconds(s["avg_duration_completed_s"]), "average time card shows %s" % MetricsData.seconds(s["avg_duration_completed_s"]))
	_expect(main.kpi_value["death_rate"].text == MetricsData.percent(s["death_rate"]), "death rate card shows %s" % MetricsData.percent(s["death_rate"]))
	_expect(main.kpi_caption["death_rate"].text == "%s / %s attempts" % [MetricsData.format_int(s["deaths"]), MetricsData.format_int(s["attempts"])],
			"death rate caption reads X / Y attempts")
	_expect(main.rounds_chart.values.size() == data.daily.size(), "the rounds chart has one bar per day (%d)" % data.daily.size())
	_expect(main.death_chart.values.size() == data.daily.size(), "the death rate chart has one point per day")
	var total_rounds := 0.0
	for value in main.rounds_chart.values:
		total_rounds += value
	_expect(int(total_rounds) == int(s["rounds"]), "the bars add up to the total number of rounds")
	_expect(main.badge.text.contains("SYNTHETIC") == data.is_synthetic(), "the badge says whether the data is synthetic")

	# Formatting helpers.
	_expect(MetricsData.format_int(141093.0) == "141,093" and MetricsData.format_int(7.0) == "7" and MetricsData.format_int(1000.0) == "1,000",
			"thousands separators")
	_expect(MetricsData.percent(0.6739) == "67.4%" and MetricsData.percent(null) == "-", "percent formatting")

	# Without data the screen says how to get it, instead of crashing.
	var missing := MetricsData.load_file("res://data/does_not_exist.json")
	_expect(not missing.ok and missing.error != "", "a missing data file gives a message, not a crash")

	print("%d check(s) failed" % failures)
	quit(1 if failures > 0 else 0)
