class_name Music
extends AudioStreamPlayer
## Background music: "Jungle Prince" (CC0), looped. It plays on the Master bus, so M mutes it with the sound effects.

const TRACK := "res://assets/music/jungle_prince.mp3"
## Quieter than the effects (Sfx.VOLUME_DB) so it stays in the background.
const VOLUME := -16.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the music keeps playing while the Esc menu pauses the game
	var track: AudioStreamMP3 = load(TRACK)
	track.loop = true
	stream = track
	volume_db = VOLUME


func _ready() -> void:
	play()
