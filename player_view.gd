class_name PlayerView
extends AnimatedSprite2D
## Draws the player from sprite strips. Purely visual: collisions still use the
## PlatformPhysics.PLAYER_SIZE box, and nothing here is read back by the game rules.

const SHEET_ROOT := "res://assets/characters/"
const ANIMATIONS := ["idle", "run", "jump", "fall", "hit"]
const FRAME_SIZE := 32
const FPS := 20.0
## The art's feet touch the bottom of the 32x32 frame, so the frame is centered
## on the hitbox and moved up/down until the two bottoms line up.
const FEET_OFFSET_Y := (PlatformPhysics.PLAYER_SIZE - FRAME_SIZE) / 2.0

## One set of animations per avatar, built on first use.
static var _frames_by_avatar := {}

var avatar := Avatars.DEFAULT


func _init() -> void:
	sprite_frames = frames_for(avatar)
	play("idle")


## Switches to another character, keeping the current animation.
func set_avatar(new_avatar: String) -> void:
	avatar = Avatars.valid(new_avatar)
	var current := animation
	sprite_frames = frames_for(avatar)
	play(current)


## Places the sprite on the body and picks the animation from its state. Facing is kept while standing still.
func sync_with(body: PlatformPhysics.Body, move_x: float) -> void:
	position = body.pos + Vector2(0.0, FEET_OFFSET_Y)
	if move_x != 0.0:
		flip_h = move_x < 0.0
	var wanted := "idle"
	if not body.on_floor:
		wanted = "jump" if body.vel.y < 0.0 else "fall"
	elif move_x != 0.0:
		wanted = "run"
	if animation != wanted:
		play(wanted)


## Plays the hit animation once where the player died. It is a separate sprite, so the
## respawn is not delayed and the event timing is unchanged.
func show_hit_at(parent: Node, body: PlatformPhysics.Body) -> void:
	var effect := AnimatedSprite2D.new()
	effect.sprite_frames = frames_for(avatar)
	effect.flip_h = flip_h
	effect.position = body.pos + Vector2(0.0, FEET_OFFSET_Y)
	effect.animation_finished.connect(effect.queue_free)
	parent.add_child(effect)
	effect.play("hit")


static func frames_for(avatar_id: String) -> SpriteFrames:
	var id := Avatars.valid(avatar_id)
	if _frames_by_avatar.has(id):
		return _frames_by_avatar[id]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in ANIMATIONS:
		var sheet: Texture2D = load("%s%s/%s.png" % [SHEET_ROOT, id, anim])
		frames.add_animation(anim)
		frames.set_animation_speed(anim, FPS)
		frames.set_animation_loop(anim, anim != "hit")
		for i in sheet.get_width() / FRAME_SIZE:
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
			frames.add_frame(anim, frame)
	_frames_by_avatar[id] = frames
	return frames
