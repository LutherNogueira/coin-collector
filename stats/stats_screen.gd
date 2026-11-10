class_name StatsScreen
extends CanvasLayer
## The statistics screen, shown over the paused game from the Esc menu. It only reads stats/data/gold.json
## (the pipeline's gold layer, bundled when the game is exported) and never changes anything.

signal closed

const DEFAULT_DATA_PATH := "res://stats/data/gold.json"

const PANEL_BG := Color(0.11, 0.14, 0.23)
const CARD_BG := Color(0.15, 0.19, 0.30)
const BORDER := Color(0.28, 0.34, 0.52)
const TEXT := Color(0.93, 0.95, 1.0)
const MUTED := Color(0.62, 0.68, 0.82)
const GOOD := Color(0.55, 0.9, 0.5)
const WARN := Color(1.0, 0.45, 0.4)
const GOLD := Color(1.0, 0.82, 0.2)

## Where the data is read from; tests point this elsewhere.
static var data_path := DEFAULT_DATA_PATH

var data: MetricsData
## Labels the tests read: key -> Label.
var kpi_value := {}
var kpi_caption := {}
var badge: Label
var rounds_chart: MetricsBarChart
var death_chart: MetricsLineChart
var message: Label

var _avatar := Avatars.DEFAULT
var _back_button: Button


func _init() -> void:
	layer = 11   # above the Esc menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func is_open() -> bool:
	return visible


## Shows the screen. `avatar` picks the character whose pictures decorate the cards.
func open(avatar: String = Avatars.DEFAULT) -> void:
	_avatar = Avatars.valid(avatar)
	_build()
	visible = true
	_back_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	kpi_value.clear()
	kpi_caption.clear()
	message = null
	data = MetricsData.load_file(data_path)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL_BG, 10))
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	if data.ok:
		column.add_child(_header())
		column.add_child(_kpi_row())
		column.add_child(_chart_row())
		column.add_child(_bottom_row())
	else:
		message = _label("No statistics in this build", 20, TEXT)
		column.add_child(message)
		column.add_child(_label(data.error + " They come from the pipeline:", 12, MUTED))
		column.add_child(_label("python -m pipeline.run_pipeline --raw <events> --out stats/data/gold.json", 11, GOLD, true))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_back_button = Button.new()
	_back_button.text = "Back  (Esc)"
	_back_button.custom_minimum_size = Vector2(140, 30)
	_back_button.pressed.connect(close)
	footer.add_child(_back_button)
	footer.add_child(_label("Statistics from the telemetry pipeline: bronze > silver > gold", 11, MUTED, true))
	column.add_child(footer)


# --- sections -------------------------------------------------------------------------------------------

func _header() -> Control:
	var row := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_label("Statistics", 22, TEXT))
	var s := data.summary
	titles.add_child(_label("%s to %s  |  generated %s" % [
		s.get("first_day", "?"), s.get("last_day", "?"),
		str(data.meta.get("generated_at", "?")).replace("T", " ").replace("Z", " UTC")], 11, MUTED, true))
	row.add_child(titles)

	badge = _label(_badge_text(), 11, WARN if data.is_synthetic() else GOOD)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", _style(CARD_BG, 6))
	holder.add_child(badge)
	row.add_child(holder)
	return row


## With only a handful of sessions the numbers are mostly the author's own test plays, and the badge says so.
const FEW_SESSIONS := 10


func _badge_text() -> String:
	if data.is_synthetic():
		return "SYNTHETIC DEMO DATA\nnot real players"
	var sessions := int(data.summary.get("sessions", 0))
	if sessions < FEW_SESSIONS:
		return "REAL PLAYS\nearly data: %s sessions" % MetricsData.format_int(sessions)
	return "REAL PLAYS"


func _kpi_row() -> Control:
	var s := data.summary
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_kpi_card(row, "rounds", _character_sheet("idle"), "Rounds", MetricsData.format_int(s.get("rounds")),
			"%s sessions" % MetricsData.format_int(s.get("sessions")))
	_kpi_card(row, "completion", "res://assets/items/fruits/apple.png", "Completion", MetricsData.percent(s.get("completion_rate")),
			"%s of %s" % [MetricsData.format_int(s.get("completed_rounds")), MetricsData.format_int(s.get("rounds"))])
	_kpi_card(row, "duration", _character_sheet("run"), "Average time", MetricsData.seconds(s.get("avg_duration_completed_s")),
			"median %s" % MetricsData.seconds(s.get("median_duration_completed_s")))
	_kpi_card(row, "death_rate", "res://assets/terrain/spikes.png", "Death rate", MetricsData.percent(s.get("death_rate")),
			"%s / %s attempts" % [MetricsData.format_int(s.get("deaths")), MetricsData.format_int(s.get("attempts"))])
	return row


func _chart_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var days: Array[String] = []
	var rounds: Array[float] = []
	var rates: Array[float] = []
	for entry in data.daily:
		days.append(str(entry["day"]).substr(5))
		rounds.append(float(entry["rounds"]))
		rates.append(float(entry["death_rate"]) if entry.get("death_rate") != null else 0.0)

	var left := _panel(row, "Rounds per day")
	rounds_chart = MetricsBarChart.new()
	rounds_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rounds_chart.set_data(rounds, days)
	left.add_child(rounds_chart)

	var right := _panel(row, "Death rate per day")
	death_chart = MetricsLineChart.new()
	death_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	death_chart.set_data(rates, days)
	right.add_child(death_chart)
	return row


func _bottom_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deaths_panel(_panel(row, "Deaths by cause", 1.0))
	_levels_panel(_panel(row, "Deadliest levels", 1.15))
	_quality_panel(_panel(row, "Data quality", 1.0))
	return row


func _deaths_panel(box: VBoxContainer) -> void:
	var total := 0.0
	for entry in data.deaths_by_cause:
		total += float(entry["deaths"])
	if data.deaths_by_cause.is_empty():
		box.add_child(_label("no deaths recorded", 11, MUTED))
	for entry in data.deaths_by_cause:
		var cause := str(entry["cause"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_icon("res://assets/terrain/spikes.png" if cause == "trap" else _character_sheet("fall"), Vector2(32, 32)))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_child(_label("%s: %s" % [cause, MetricsData.format_int(entry["deaths"])], 12, TEXT, true))
		var bar := ColorRect.new()
		bar.color = WARN if cause == "trap" else GOLD
		bar.custom_minimum_size = Vector2(maxf(4.0, 90.0 * float(entry["share"])), 5)
		details.add_child(bar)
		details.add_child(_label("%s of %s" % [MetricsData.percent(entry["share"]), MetricsData.format_int(total)], 10, MUTED, true))
		row.add_child(details)
		box.add_child(row)


func _levels_panel(box: VBoxContainer) -> void:
	box.add_child(_label("deaths / attempts", 10, MUTED))
	if data.deadliest_levels.is_empty():
		box.add_child(_label("not enough attempts yet", 11, MUTED))
	var shown := 0
	for entry in data.deadliest_levels:
		if shown >= 4:
			break
		shown += 1
		var name := "hand-made level" if int(entry["level_seed"]) == 0 else "seed %d" % int(entry["level_seed"])
		box.add_child(_label("%d. %s: %s/%s  %s" % [
			shown, name, MetricsData.format_int(entry["deaths"]), MetricsData.format_int(entry["attempts"]),
			MetricsData.percent(entry["death_rate"])], 11, TEXT, true))


func _quality_panel(box: VBoxContainer) -> void:
	var s := data.summary
	box.add_child(_label("Bronze: %s lines" % MetricsData.format_int(s.get("bronze_lines")), 11, TEXT, true))
	box.add_child(_label("Silver: %s clean" % MetricsData.format_int(s.get("silver_events")), 11, GOOD, true))
	box.add_child(_label("Quarantine: %s (%s)" % [MetricsData.format_int(s.get("quarantined_lines")),
			MetricsData.percent(s.get("quarantine_rate"))], 11, WARN, true))
	var shown := 0
	for entry in data.data_quality:
		if shown >= 3:
			break
		shown += 1
		box.add_child(_label("  %s: %s" % [entry["reason"], MetricsData.format_int(entry["lines"])], 10, MUTED, true))
	if data.data_quality.size() > shown:
		box.add_child(_label("  ... and %d more reasons" % (data.data_quality.size() - shown), 10, MUTED, true))


# --- building blocks ------------------------------------------------------------------------------------

func _character_sheet(animation: String) -> String:
	return "%s%s/%s.png" % [PlayerView.SHEET_ROOT, _avatar, animation]


func _kpi_card(parent: Control, key: String, icon_path: String, title: String, value: String, caption: String) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(CARD_BG, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon(icon_path, Vector2(32, 32)))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(_label(title, 10, MUTED, true))
	var big := _label(value, 22, TEXT)
	texts.add_child(big)
	var small := _label(caption, 10, MUTED, true)
	texts.add_child(small)
	row.add_child(texts)
	card.add_child(row)
	parent.add_child(card)
	kpi_value[key] = big
	kpi_caption[key] = small


## The first frame of a strip (frames are as tall as the strip) or a single sprite, shown at a whole-number zoom.
func _icon(sheet_path: String, box: Vector2) -> TextureRect:
	var sheet: Texture2D = load(sheet_path)
	var side := sheet.get_height()
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, side, side)
	var rect := TextureRect.new()
	rect.texture = atlas
	rect.custom_minimum_size = box
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


func _panel(parent: Control, title: String, stretch: float = 1.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch
	panel.add_theme_stylebox_override("panel", _style(CARD_BG, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(_label(title, 12, GOLD))
	panel.add_child(box)
	parent.add_child(panel)
	return box


func _style(color: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_content_margin_all(margin)
	return style


## `trim` lets a long text shrink with an ellipsis instead of making its container wider.
func _label(text: String, size: int, color: Color, trim: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if trim:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
