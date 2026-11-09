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


static func save_avatar(avatar: String) -> void:
	var config := ConfigFile.new()
	config.load(path)   # keep other settings if the file already exists
	config.set_value("player", "avatar", Avatars.valid(avatar))
	config.save(path)
