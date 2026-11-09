class_name MetricsLineChart
extends Control
## A line for values between 0 and 1 (rates), drawn on a 0-100% axis with the last value written next to it.

const AXIS := Color(0.45, 0.52, 0.7)
const GRID := Color(0.3, 0.36, 0.52, 0.6)
const MUTED := Color(0.62, 0.68, 0.82)
const FONT_SIZE := 11

var values: Array[float] = []
var labels: Array[String] = []
var line_color := Color(1.0, 0.45, 0.4)


func set_data(new_values: Array[float], new_labels: Array[String]) -> void:
	values = new_values
	labels = new_labels
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var plot := Rect2(40.0, 6.0, size.x - 80.0, size.y - 26.0)
	for step: float in [0.0, 0.5, 1.0]:
		var y := plot.end.y - plot.size.y * step
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), AXIS if step == 0.0 else GRID, 1.0)
		draw_string(font, Vector2(2, y + 4.0), "%d%%" % int(step * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
	if values.is_empty():
		draw_string(font, plot.position + Vector2(8, 24), "no data", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		return

	var points := PackedVector2Array()
	var slot := plot.size.x / maxf(values.size() - 1, 1)
	for i in values.size():
		points.append(Vector2(plot.position.x + i * slot, plot.end.y - plot.size.y * clampf(values[i], 0.0, 1.0)))
	if points.size() > 1:
		draw_polyline(points, line_color, 2.0, true)
	draw_circle(points[points.size() - 1], 3.5, line_color)
	draw_string(font, points[points.size() - 1] + Vector2(8, 4), "%.0f%%" % (values[values.size() - 1] * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, line_color)

	for index: int in [0, values.size() / 2, values.size() - 1]:
		var text := labels[index] if index < labels.size() else ""
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var x := clampf(plot.position.x + index * slot - width / 2.0, 0.0, size.x - width)
		draw_string(font, Vector2(x, size.y - 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
