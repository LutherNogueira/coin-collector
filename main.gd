extends Node2D

const COIN_RADIUS := 12.0
const SAMPLE_INTERVAL := 0.5

enum State { PLAYING, ENDED }

var logger := EventLogger.new()
var state := State.PLAYING

var level: Level
var body: PlatformPhysics.Body
var t := 0.0
var next_sample_t := SAMPLE_INTERVAL
var collected: Array[bool] = []
var coin_spawn_t: Array[float] = []

var rounds_started := 0
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


## The first round of a session plays the hand-made level (seed 0); later rounds get a random seed.
func _start_round() -> void:
	if state == State.PLAYING and logger.round_id != null:
		_end_round()
	var level_seed := 0 if rounds_started == 0 else randi_range(1, 2147483647)
	rounds_started += 1
	level = Level.hand_made() if level_seed == 0 else Level.generate(level_seed)
	t = 0.0
	next_sample_t = SAMPLE_INTERVAL
	coins_collected = 0
	deaths = 0
	jumps = 0
	position_samples = 0
	completed = false
	state = State.PLAYING
	logger.new_round()
	logger.log_event("round_start", {"t": 0.0, "level_seed": level_seed})
	_reset_level()


## Puts the player back at the start and restores every coin.
func _reset_level() -> void:
	body = PlatformPhysics.Body.new(Level.START_POS)
	collected.clear()
	coin_spawn_t.clear()
	for i in level.coins.size():
		collected.append(false)
		coin_spawn_t.append(t)
		logger.log_event("coin_spawn", {"t": _r(t, 0.001), "coin_id": i, "x": _r(level.coins[i].x), "y": _r(level.coins[i].y)})


## Advances the simulation by `delta` seconds. Free of input reads so tests can drive it.
func _step(delta: float, move_x: float, jump_pressed: bool) -> void:
	var remaining := delta
	var jump := jump_pressed
	while remaining > 0.0 and state == State.PLAYING:
		var h := minf(remaining, PlatformPhysics.SUBSTEP)
		remaining -= h
		_substep(h, move_x, jump)
		jump = false


func _substep(h: float, move_x: float, jump_pressed: bool) -> void:
	t += h
	var result := PlatformPhysics.step(body, level, h, move_x, jump_pressed)
	if result["jumped"]:
		jumps += 1
		var from: Vector2 = result["jump_pos"]
		logger.log_event("player_jump", {"t": _r(t, 0.001), "x": _r(from.x), "y": _r(from.y)})
	if result["landing_speed"] > 0.0:
		var payload := _pos_payload()
		payload["vy"] = _r(result["landing_speed"])
		logger.log_event("player_land", payload)

	while t >= next_sample_t:
		position_samples += 1
		var sample := _pos_payload()
		sample["t"] = _r(next_sample_t, 0.001)
		logger.log_event("player_position", sample)
		next_sample_t += SAMPLE_INTERVAL

	for i in level.coins.size():
		if not collected[i] and PlatformPhysics.circle_hits(body, level.coins[i], COIN_RADIUS):
			collected[i] = true
			coins_collected += 1
			logger.log_event("coin_collect", {
				"t": _r(t, 0.001), "coin_id": i, "x": _r(level.coins[i].x), "y": _r(level.coins[i].y),
				"dt": _r(t - coin_spawn_t[i], 0.001),
			})

	var cause := PlatformPhysics.death_cause(body, level)
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


func _end_round() -> void:
	state = State.ENDED
	logger.log_event("round_end", {
		"t": _r(t, 0.001),
		"completed": completed,
		"coins_collected": coins_collected,
		"coins_total": level.coins.size(),
		"deaths": deaths,
		"jumps": jumps,
		"position_samples": position_samples,
		"duration_s": _r(t, 0.001),
	})
	logger.close_round()


func _pos_payload() -> Dictionary:
	return {"t": _r(t, 0.001), "x": _r(body.pos.x), "y": _r(body.pos.y)}


func _r(value: float, step: float = 0.1) -> float:
	return snappedf(value, step)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Level.ARENA), Color(0.1, 0.1, 0.14))
	for s: Rect2 in level.solids:
		draw_rect(s, Color(0.35, 0.38, 0.45))
	for trap: Rect2 in level.traps:
		var teeth := maxi(int(trap.size.x / 10.0), 1)
		var w := trap.size.x / teeth
		for i in teeth:
			var x0 := trap.position.x + i * w
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0, trap.end.y), Vector2(x0 + w / 2.0, trap.position.y), Vector2(x0 + w, trap.end.y),
			]), Color(0.9, 0.2, 0.2))
	for i in level.coins.size():
		if not collected[i]:
			draw_circle(level.coins[i], COIN_RADIUS, Color(1.0, 0.82, 0.2))
	draw_rect(body.rect(), Color(0.3, 0.8, 1.0))

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, 28), "Coins: %d/%d   Deaths: %d" % [collected.count(true), level.coins.size(), deaths], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string(font, Vector2(12, Level.ARENA.y - 12), "Level %s" % ("0 (hand-made)" if level.seed_value == 0 else str(level.seed_value)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	if state == State.ENDED:
		draw_string(font, Vector2(0, 220), "Level complete!", HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x, 40)
		draw_string(font, Vector2(0, 270), "Time: %.1f s   Deaths: %d" % [t, deaths], HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x, 26)
		draw_string(font, Vector2(0, 315), "Press Enter for a new level", HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x, 22)
