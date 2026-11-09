class_name MetricsBarChart
extends Control
## A bar per value, with the highest value and a few labels written on the axes.

const AXIS := Color(0.45, 0.52, 0.7)
const MUTED := Color(0.62, 0.68, 0.82)
const FONT_SIZE := 11

var values: Array[float] = []
var labels: Array[String] = []
var bar_color := Color(0.4, 0.8, 1.0)


func set_data(new_values: Array[float], new_labels: Array[String]) -> void:
	values = new_values
	labels = new_labels
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var plot := Rect2(34.0, 6.0, size.x - 40.0, size.y - 26.0)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, AXIS, 1.0)
	if values.is_empty():
		draw_string(font, plot.position + Vector2(8, 24), "no data", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
		return

	var top := 1.0
	for value in values:
		top = maxf(top, value)
	draw_string(font, Vector2(2, plot.position.y + 10), str(int(top)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
	draw_string(font, Vector2(2, plot.end.y), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)

	var slot := plot.size.x / values.size()
	for i in values.size():
		var height := plot.size.y * values[i] / top
		draw_rect(Rect2(plot.position.x + i * slot + 1.0, plot.end.y - height, maxf(slot - 2.0, 1.0), height), bar_color)

	for index: int in [0, values.size() / 2, values.size() - 1]:
		var text := labels[index] if index < labels.size() else ""
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var x := clampf(plot.position.x + index * slot - width / 2.0 + slot / 2.0, 0.0, size.x - width)
		draw_string(font, Vector2(x, size.y - 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
