extends Control
## The metrics screen: headline numbers, two charts, and breakdowns of deaths, levels and data quality.
## It only reads data/gold.json (the pipeline's gold layer) and never changes anything.

const DATA_PATH := "res://data/gold.json"

const PANEL_BG := Color(0.13, 0.16, 0.26)
const PANEL_BORDER := Color(0.28, 0.34, 0.52)
const TEXT := Color(0.93, 0.95, 1.0)
const MUTED := Color(0.62, 0.68, 0.82)
const GOOD := Color(0.55, 0.9, 0.5)
const WARN := Color(1.0, 0.45, 0.4)
const GOLD := Color(1.0, 0.82, 0.2)

var data: MetricsData
## Labels the tests read: key -> Label.
var kpi_value := {}
var kpi_caption := {}
var badge: Label
var rounds_chart: MetricsBarChart
var death_chart: MetricsLineChart

var _idle: Texture2D = load("res://assets/characters/idle.png")
var _run: Texture2D = load("res://assets/characters/run.png")
var _fall: Texture2D = load("res://assets/characters/fall.png")
var _apple: Texture2D = load("res://assets/items/apple.png")
var _spikes: Texture2D = load("res://assets/terrain/spikes.png")
var _background: Texture2D = load("res://assets/background/blue.png")


func _ready() -> void:
	_add_background()
	data = MetricsData.load_file(DATA_PATH)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	if not data.ok:
		column.add_child(_label("No data to show", 26, TEXT))
		column.add_child(_label(data.error + " Generate it with:", 14, MUTED))
		column.add_child(_label("python -m pipeline.run_pipeline --raw <events folder> --out metrics_app/data/gold.json", 13, GOLD))
		return

	column.add_child(_header())
	column.add_child(_kpi_row())
	column.add_child(_chart_row())
	column.add_child(_bottom_row())


func _add_background() -> void:
	var sky := TextureRect.new()
	sky.texture = _background
	sky.stretch_mode = TextureRect.STRETCH_TILE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.self_modulate = Color(0.28, 0.32, 0.5)   # darkened, so the panels and text stand out
	add_child(sky)


# --- sections -------------------------------------------------------------------------------------------

func _header() -> Control:
	var row := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_label("Coin Collector - Telemetry", 26, TEXT))
	var s := data.summary
	titles.add_child(_label("Data from %s to %s  |  generated %s  |  bronze > silver > gold" % [
		s.get("first_day", "?"), s.get("last_day", "?"), str(data.meta.get("generated_at", "?")).replace("T", " ").replace("Z", " UTC")],
		12, MUTED))
	row.add_child(titles)

	badge = _label("SYNTHETIC DEMO DATA\nnot real players" if data.is_synthetic() else "REAL PLAYS", 13, WARN if data.is_synthetic() else GOOD)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var holder := _panel_box()
	holder.add_child(badge)
	row.add_child(holder)
	return row


func _kpi_row() -> Control:
	var s := data.summary
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_kpi_card(row, "rounds", _idle, 0, "Rounds", MetricsData.format_int(s.get("rounds")),
			"%s sessions" % MetricsData.format_int(s.get("sessions")))
	_kpi_card(row, "completion", _apple, 0, "Completion rate", MetricsData.percent(s.get("completion_rate")),
			"%s of %s completed" % [MetricsData.format_int(s.get("completed_rounds")), MetricsData.format_int(s.get("rounds"))])
	_kpi_card(row, "duration", _run, 0, "Average time (completed rounds)", MetricsData.seconds(s.get("avg_duration_completed_s")),
			"median %s" % MetricsData.seconds(s.get("median_duration_completed_s")))
	_kpi_card(row, "death_rate", _spikes, 0, "Death rate", MetricsData.percent(s.get("death_rate")),
			"%s / %s attempts" % [MetricsData.format_int(s.get("deaths")), MetricsData.format_int(s.get("attempts"))])
	return row


func _chart_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var days: Array[String] = []
	var rounds: Array[float] = []
	var rates: Array[float] = []
	for entry in data.daily:
		days.append(str(entry["day"]).substr(5))
		rounds.append(float(entry["rounds"]))
		rates.append(float(entry["death_rate"]) if entry.get("death_rate") != null else 0.0)

	var left := _panel(row, "Rounds per day", Vector2(0, 150))
	rounds_chart = MetricsBarChart.new()
	rounds_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rounds_chart.set_data(rounds, days)
	left.add_child(rounds_chart)

	var right := _panel(row, "Death rate per day (deaths / attempts)", Vector2(0, 150))
	death_chart = MetricsLineChart.new()
	death_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	death_chart.set_data(rates, days)
	right.add_child(death_chart)
	return row


func _bottom_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deaths_panel(_panel(row, "Deaths by cause", Vector2(0, 150), 25))
	_levels_panel(_panel(row, "Deadliest levels", Vector2(0, 150), 38))
	_quality_panel(_panel(row, "Data quality", Vector2(0, 150), 30))
	return row


func _deaths_panel(box: VBoxContainer) -> void:
	var total := 0.0
	for entry in data.deaths_by_cause:
		total += float(entry["deaths"])
	if data.deaths_by_cause.is_empty():
		box.add_child(_label("no deaths recorded", 13, MUTED))
	for entry in data.deaths_by_cause:
		var cause := str(entry["cause"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon(_spikes if cause == "trap" else _fall, 0, Vector2(32, 32)))
		var details := VBoxContainer.new()
		details.add_child(_label("%s: %s deaths" % [cause, MetricsData.format_int(entry["deaths"])], 13, TEXT))
		var bar := ColorRect.new()
		bar.color = WARN if cause == "trap" else GOLD
		bar.custom_minimum_size = Vector2(maxf(4.0, 150.0 * float(entry["share"])), 6)
		details.add_child(bar)
		details.add_child(_label("%s of %s deaths" % [MetricsData.percent(entry["share"]), MetricsData.format_int(total)], 11, MUTED))
		row.add_child(details)
		box.add_child(row)


func _levels_panel(box: VBoxContainer) -> void:
	box.add_child(_label("deaths / attempts; a level is its seed + generator version", 11, MUTED, true))
	if data.deadliest_levels.is_empty():
		box.add_child(_label("not enough attempts yet", 13, MUTED))
	var shown := 0
	for entry in data.deadliest_levels:
		if shown >= 5:
			break
		shown += 1
		var name := "hand-made level" if int(entry["level_seed"]) == 0 else "seed %d" % int(entry["level_seed"])
		box.add_child(_label("%d. %s (gen %d):  %s / %s  =  %s" % [
			shown, name, int(entry["generator_version"]), MetricsData.format_int(entry["deaths"]),
			MetricsData.format_int(entry["attempts"]), MetricsData.percent(entry["death_rate"])], 12, TEXT, true))


func _quality_panel(box: VBoxContainer) -> void:
	var s := data.summary
	box.add_child(_label("Bronze:  %s lines" % MetricsData.format_int(s.get("bronze_lines")), 13, TEXT))
	box.add_child(_label("Silver:  %s clean events" % MetricsData.format_int(s.get("silver_events")), 13, GOOD))
	box.add_child(_label("Quarantine:  %s lines (%s)" % [MetricsData.format_int(s.get("quarantined_lines")),
			MetricsData.percent(s.get("quarantine_rate"))], 13, WARN))
	var shown := 0
	for entry in data.data_quality:
		if shown >= 4:
			break
		shown += 1
		box.add_child(_label("  %s: %s" % [entry["reason"], MetricsData.format_int(entry["lines"])], 11, MUTED))
	if data.data_quality.size() > shown:
		box.add_child(_label("  ... and %d more reasons" % (data.data_quality.size() - shown), 11, MUTED))


# --- building blocks ------------------------------------------------------------------------------------

func _kpi_card(parent: Control, key: String, icon: Texture2D, icon_frame: int, title: String, value: String, caption: String) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_icon(icon, icon_frame, Vector2(64, 64)))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(_label(title, 12, MUTED))
	var big := _label(value, 28, TEXT)
	texts.add_child(big)
	var small := _label(caption, 11, MUTED, true)
	texts.add_child(small)
	row.add_child(texts)
	card.add_child(row)
	parent.add_child(card)
	kpi_value[key] = big
	kpi_caption[key] = small


## An animation strip's frame (frames are as tall as the strip) or a single sprite, shown at a whole-number zoom.
func _icon(sheet: Texture2D, frame: int, box: Vector2) -> TextureRect:
	var side := sheet.get_height()
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(frame * side, 0, side, side)
	var rect := TextureRect.new()
	rect.texture = atlas
	rect.custom_minimum_size = box
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


func _panel(parent: Control, title: String, min_size: Vector2, stretch: float = 1.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", _style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label(title, 14, GOLD))
	panel.add_child(box)
	parent.add_child(panel)
	return box


func _panel_box() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	return panel


func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	return style


## `trim` lets a long text shrink with an ellipsis instead of making its container wider.
func _label(text: String, size: int, color: Color, trim: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	if trim:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
