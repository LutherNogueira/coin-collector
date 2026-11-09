class_name Avatars
extends RefCounted
## The playable characters. Each id is a folder in assets/characters/ with idle, run, jump, fall and hit strips.

const DEFAULT := "ninja_frog"
const NAMES := {
	"ninja_frog": "Ninja Frog",
	"mask_dude": "Mask Dude",
	"pink_man": "Pink Man",
	"virtual_guy": "Virtual Guy",
}


static func ids() -> Array:
	return NAMES.keys()


static func display_name(id: String) -> String:
	return NAMES.get(id, NAMES[DEFAULT])


## The id itself when it is a known avatar, otherwise the default (a saved choice can be stale or edited).
static func valid(id: String) -> String:
	return id if NAMES.has(id) else DEFAULT


## The avatar `step` places after `id`, wrapping around (-1 goes back).
static func shifted(id: String, step: int) -> String:
	var all := ids()
	return all[posmod(all.find(valid(id)) + step, all.size())]
