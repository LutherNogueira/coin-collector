class_name EventLogger
extends RefCounted
## Appends one JSON object per line (JSON Lines) to user://events.jsonl.
## Every line: {"timestamp", "evento", "valor", "session_id", "round_id", "schema_version"}.

const LOG_PATH := "user://events.jsonl"
const SCHEMA_VERSION := 3

## Where events are appended; tests point this at their own file.
var log_path := LOG_PATH
var session_id: String = _uuid4()
var round_id: Variant = null


func new_round() -> void:
	round_id = _uuid4()


func close_round() -> void:
	round_id = null


func log_event(evento: String, valor: Dictionary = {}) -> void:
	var line := JSON.stringify({
		"timestamp": _timestamp(),
		"evento": evento,
		"valor": valor,
		"session_id": session_id,
		"round_id": round_id,
		"schema_version": SCHEMA_VERSION,
	})
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if file == null:
		push_error("Could not open %s (error %d)" % [log_path, FileAccess.get_open_error()])
		return
	file.seek_end()
	file.store_line(line)


func absolute_path() -> String:
	return ProjectSettings.globalize_path(log_path)


func _timestamp() -> String:
	var unix := Time.get_unix_time_from_system()
	var secs := int(unix)
	var ms := int((unix - secs) * 1000.0)
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(secs), ms]


func _uuid4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
