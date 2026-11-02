class_name Sfx
extends Node
## Plays the sound effects in assets/sounds (made by tools/generate_sfx.py). Press M in game to mute.

const DIR := "res://assets/sounds/"
const NAMES := ["jump", "collect", "death", "win"]
const VOLUME_DB := -8.0

var _players := {}


func _init() -> void:
	for sound_name in NAMES:
		var player := AudioStreamPlayer.new()
		player.stream = load(DIR + sound_name + ".wav")
		player.volume_db = VOLUME_DB
		add_child(player)
		_players[sound_name] = player


func play(sound_name: String) -> void:
	(_players[sound_name] as AudioStreamPlayer).play()


func toggle_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))
