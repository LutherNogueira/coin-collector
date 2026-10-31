extends Node2D

const ARENA := Vector2(800, 600)
const PLAYER_SIZE := 24.0
const MOVE_SPEED := 240.0
const JUMP_SPEED := 560.0
const GRAVITY := 1500.0
const MAX_FALL_SPEED := 900.0
const SUBSTEP := 1.0 / 120.0
const COIN_RADIUS := 12.0
const SAMPLE_INTERVAL := 0.5
const START_POS := Vector2(40, 528)

## Solid platforms: the player stands on them and cannot pass through.
const SOLIDS := [
	Rect2(0, 540, 300, 60),
	Rect2(380, 540, 180, 60),
	Rect2(640, 540, 160, 60),
	Rect2(440, 480, 40, 60),
	Rect2(170, 450, 110, 16),
	Rect2(330, 370, 110, 16),
	Rect2(520, 300, 100, 16),
	Rect2(670, 420, 120, 16),
]
## Traps kill on contact. Falling into a gap in the ground also kills ("pit").
const TRAPS := [
	Rect2(100, 524, 40, 16),
	Rect2(500, 524, 40, 16),
	Rect2(715, 404, 30, 16),
]
const COINS := [
	Vector2(120, 470),
	Vector2(225, 428),
	Vector2(340, 470),
	Vector2(385, 348),
	Vector2(570, 278),
	Vector2(600, 470),
	Vector2(768, 398),
]

enum State { PLAYING, ENDED }

var logger := EventLogger.new()
var state := State.PLAYING

var t := 0.0
var player_pos := START_POS
var velocity := Vector2.ZERO
var on_floor := true
var collected: Array[bool] = []
var coin_spawn_t: Array[float] = []
var next_sample_t := SAMPLE_INTERVAL

var coins_collected := 0
var deaths := 0
var jumps := 0
var position_samples := 0
var completed := false
var jump_was_down := false


func _ready() -> void:
	logger.log_event("session_start")
	_start_round()


func _process(delta: float) -> void:
	var jump_down := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)
	_step(delta, _read_move_x(), jump_down and not jump_was_down)
	jump_was_down = jump_down
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.ENDED and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_start_round()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state == State.PLAYING:
			_end_round()
		logger.log_event("session_end")


func _read_move_x() -> float:
	var x := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		x += 1.0
	return x


func _start_round() -> void:
	if state == State.PLAYING and logger.round_id != null:
		_end_round()
	t = 0.0
	next_sample_t = SAMPLE_INTERVAL
	coins_collected = 0
	deaths = 0
	jumps = 0
	position_samples = 0
	completed = false
	state = State.PLAYING
	logger.new_round()
	logger.log_event("round_start", {"t": 0.0})
	_reset_level()


## Puts the player back at the start and restores every coin.
func _reset_level() -> void:
	player_pos = START_POS
	velocity = Vector2.ZERO
	on_floor = true
	collected.clear()
	coin_spawn_t.clear()
	for i in COINS.size():
		collected.append(false)
		coin_spawn_t.append(t)
		logger.log_event("coin_spawn", {"t": _r(t, 0.001), "coin_id": i, "x": _r(COINS[i].x), "y": _r(COINS[i].y)})


## Advances the simulation by `delta` seconds. Free of input reads so tests can drive it.
func _step(delta: float, move_x: float, jump_pressed: bool) -> void:
	var remaining := delta
	var jump := jump_pressed
	while remaining > 0.0 and state == State.PLAYING:
		var h := minf(remaining, SUBSTEP)
		remaining -= h
		_substep(h, move_x, jump)
		jump = false


func _substep(h: float, move_x: float, jump_pressed: bool) -> void:
	t += h
	var half := PLAYER_SIZE / 2.0
	var was_on_floor := on_floor

	velocity.x = move_x * MOVE_SPEED
	if jump_pressed and on_floor:
		velocity.y = -JUMP_SPEED
		on_floor = false
		was_on_floor = false
		jumps += 1
		logger.log_event("player_jump", _pos_payload())
	velocity.y = minf(velocity.y + GRAVITY * h, MAX_FALL_SPEED)

	player_pos.x = clampf(player_pos.x + velocity.x * h, half, ARENA.x - half)
	for s: Rect2 in SOLIDS:
		if _player_rect().intersects(s):
			if velocity.x > 0.0:
				player_pos.x = s.position.x - half
			elif velocity.x < 0.0:
				player_pos.x = s.end.x + half

	player_pos.y += velocity.y * h
	on_floor = false
	var landing_speed := 0.0
	for s: Rect2 in SOLIDS:
		if _player_rect().intersects(s):
			if velocity.y > 0.0:
				player_pos.y = s.position.y - half
				on_floor = true
				landing_speed = velocity.y
			elif velocity.y < 0.0:
				player_pos.y = s.end.y + half
			velocity.y = 0.0
	if on_floor and not was_on_floor:
		var payload := _pos_payload()
		payload["vy"] = _r(landing_speed)
		logger.log_event("player_land", payload)

	while t >= next_sample_t:
		position_samples += 1
		var sample := _pos_payload()
		sample["t"] = _r(next_sample_t, 0.001)
		logger.log_event("player_position", sample)
		next_sample_t += SAMPLE_INTERVAL

	for i in COINS.size():
		if not collected[i] and _circle_hits_player(COINS[i], COIN_RADIUS):
			collected[i] = true
			coins_collected += 1
			logger.log_event("coin_collect", {
				"t": _r(t, 0.001), "coin_id": i, "x": _r(COINS[i].x), "y": _r(COINS[i].y),
				"dt": _r(t - coin_spawn_t[i], 0.001),
			})

	var cause := _death_cause()
	if cause != "":
		deaths += 1
		var death := _pos_payload()
		death["cause"] = cause
		logger.log_event("player_death", death)
		_reset_level()
		logger.log_event("player_respawn", _pos_payload())
		return

	if not collected.has(false):
		completed = true
		_end_round()


func _death_cause() -> String:
	if player_pos.y - PLAYER_SIZE / 2.0 > ARENA.y:
		return "pit"
	for trap: Rect2 in TRAPS:
		if _player_rect().intersects(trap):
			return "trap"
	return ""


func _end_round() -> void:
	state = State.ENDED
	logger.log_event("round_end", {
		"t": _r(t, 0.001),
		"completed": completed,
		"coins_collected": coins_collected,
		"coins_total": COINS.size(),
		"deaths": deaths,
		"jumps": jumps,
		"position_samples": position_samples,
		"duration_s": _r(t, 0.001),
	})
	logger.close_round()


func _pos_payload() -> Dictionary:
	return {"t": _r(t, 0.001), "x": _r(player_pos.x), "y": _r(player_pos.y)}


func _player_rect() -> Rect2:
	var half := Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0
	return Rect2(player_pos - half, half * 2.0)


func _circle_hits_player(center: Vector2, radius: float) -> bool:
	var half := Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0
	var closest := center.clamp(player_pos - half, player_pos + half)
	return closest.distance_to(center) <= radius


func _r(value: float, step: float = 0.1) -> float:
	return snappedf(value, step)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.1, 0.1, 0.14))
	for s: Rect2 in SOLIDS:
		draw_rect(s, Color(0.35, 0.38, 0.45))
	for trap: Rect2 in TRAPS:
		var teeth := maxi(int(trap.size.x / 10.0), 1)
		var w := trap.size.x / teeth
		for i in teeth:
			var x0 := trap.position.x + i * w
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0, trap.end.y), Vector2(x0 + w / 2.0, trap.position.y), Vector2(x0 + w, trap.end.y),
			]), Color(0.9, 0.2, 0.2))
	for i in COINS.size():
		if not collected[i]:
			draw_circle(COINS[i], COIN_RADIUS, Color(1.0, 0.82, 0.2))
	draw_rect(_player_rect(), Color(0.3, 0.8, 1.0))

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, 28), "Coins: %d/%d   Deaths: %d" % [_collected_count(), COINS.size(), deaths], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	if state == State.ENDED:
		draw_string(font, Vector2(0, 220), "Level complete!", HORIZONTAL_ALIGNMENT_CENTER, ARENA.x, 40)
		draw_string(font, Vector2(0, 270), "Time: %.1f s   Deaths: %d" % [t, deaths], HORIZONTAL_ALIGNMENT_CENTER, ARENA.x, 26)
		draw_string(font, Vector2(0, 315), "Press Enter to play again", HORIZONTAL_ALIGNMENT_CENTER, ARENA.x, 22)


func _collected_count() -> int:
	return collected.count(true)
