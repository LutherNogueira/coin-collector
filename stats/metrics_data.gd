class_name MetricsData
extends RefCounted
## The gold tables exported by the pipeline (data/gold.json), plus the formatting the screen needs.

var ok := false
var error := ""
var meta := {}
var summary := {}
var daily: Array = []
var deaths_by_cause: Array = []
var deadliest_levels: Array = []
var data_quality: Array = []


static func load_file(path: String) -> MetricsData:
	var data := MetricsData.new()
	if not FileAccess.file_exists(path):
		data.error = "There is no data file yet."
		return data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("summary") or not parsed.has("daily_metrics"):
		data.error = "The data file is not a pipeline export."
		return data
	data.meta = parsed.get("meta", {})
	data.summary = parsed["summary"]
	data.daily = parsed["daily_metrics"]
	data.deaths_by_cause = parsed.get("deaths_by_cause", [])
	data.deadliest_levels = parsed.get("deadliest_levels", [])
	data.data_quality = parsed.get("data_quality", [])
	data.ok = true
	return data


func is_synthetic() -> bool:
	return str(meta.get("source", "")).to_lower().contains("synthetic")


## 141093 -> "141,093" (JSON numbers arrive as floats).
static func format_int(value: Variant) -> String:
	if value == null:
		return "-"
	var digits := str(int(roundf(float(value))))
	var out := ""
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		var from_end := digits.length() - i
		if from_end % 3 == 0 and i > 0 and digits[i - 1] != "-":
			out = "," + out
	return out


## 0.6739 -> "67.4%"
static func percent(value: Variant) -> String:
	if value == null:
		return "-"
	return "%.1f%%" % (float(value) * 100.0)


## 28.43 -> "28.4 s"
static func seconds(value: Variant) -> String:
	if value == null:
		return "-"
	return "%.1f s" % float(value)
