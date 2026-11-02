class_name PlatformPhysics
extends RefCounted
## Small kinematic physics: gravity, jumping and axis-separated rectangle collisions.
## Pure functions over a Body, so the game and the level verifier run the exact same simulation.

const PLAYER_SIZE := 24.0
const MOVE_SPEED := 240.0
const JUMP_SPEED := 560.0
const GRAVITY := 1500.0
const MAX_FALL_SPEED := 900.0
## Fixed simulation substep; callers advance time in multiples of it.
const SUBSTEP := 1.0 / 120.0


class Body:
	var pos: Vector2
	var vel := Vector2.ZERO
	var on_floor := true

	func _init(start: Vector2) -> void:
		pos = start

	func rect() -> Rect2:
		var half := Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0
		return Rect2(pos - half, half * 2.0)


## Advances `body` by one substep `h`. Returns {jumped, jump_pos, landing_speed}.
static func step(body: Body, level: Level, h: float, move_x: float, jump: bool) -> Dictionary:
	var half := PLAYER_SIZE / 2.0
	var was_on_floor := body.on_floor
	var result := {"jumped": false, "jump_pos": Vector2.ZERO, "landing_speed": 0.0}

	body.vel.x = move_x * MOVE_SPEED
	if jump and body.on_floor:
		result["jumped"] = true
		result["jump_pos"] = body.pos
		body.vel.y = -JUMP_SPEED
		body.on_floor = false
		was_on_floor = false
	body.vel.y = minf(body.vel.y + GRAVITY * h, MAX_FALL_SPEED)

	body.pos.x = clampf(body.pos.x + body.vel.x * h, half, Level.ARENA.x - half)
	for s: Rect2 in level.solids:
		if body.rect().intersects(s):
			if body.vel.x > 0.0:
				body.pos.x = s.position.x - half
			elif body.vel.x < 0.0:
				body.pos.x = s.end.x + half

	body.pos.y += body.vel.y * h
	body.on_floor = false
	var landing_speed := 0.0
	for s: Rect2 in level.solids:
		if body.rect().intersects(s):
			if body.vel.y > 0.0:
				body.pos.y = s.position.y - half
				body.on_floor = true
				landing_speed = body.vel.y
			elif body.vel.y < 0.0:
				body.pos.y = s.end.y + half
			body.vel.y = 0.0
	if body.on_floor and not was_on_floor:
		result["landing_speed"] = landing_speed
	return result


## "trap", "pit" or "" when the body is alive.
static func death_cause(body: Body, level: Level) -> String:
	if body.pos.y - PLAYER_SIZE / 2.0 > Level.ARENA.y:
		return "pit"
	for trap: Rect2 in level.traps:
		if body.rect().intersects(Level.trap_hitbox(trap)):
			return "trap"
	return ""


static func circle_hits(body: Body, center: Vector2, radius: float) -> bool:
	var closest := center.clamp(body.pos - Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0, body.pos + Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0)
	return closest.distance_to(center) <= radius
