class_name Settings
extends RefCounted
## What the player chose, kept between visits in user://settings.cfg (in the browser's storage on the web).
## It is a personal preference and is not part of the telemetry events.

static var path := "user://settings.cfg"


static func load_avatar() -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return Avatars.DEFAULT
	return Avatars.valid(str(config.get_value("player", "avatar", Avatars.DEFAULT)))


## Whether anonymous match statistics may be sent (web build). On unless the player turned it off.
static func load_telemetry() -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return true
	return bool(config.get_value("privacy", "send_stats", true))


static func save_telemetry(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("privacy", "send_stats", enabled)
	config.save(path)


## The first visit shows a short notice about the statistics; once it has been shown it is not shown again.
static func notice_seen() -> bool:
	var config := ConfigFile.new()
	return config.load(path) == OK and bool(config.get_value("privacy", "notice_seen", false))


static func mark_notice_seen() -> void:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("privacy", "notice_seen", true)
	config.save(path)


static func save_avatar(avatar: String) -> void:
	var config := ConfigFile.new()
	config.load(path)   # keep other settings if the file already exists
	config.set_value("player", "avatar", Avatars.valid(avatar))
	config.save(path)
