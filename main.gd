extends Node2D

const ARENA := Vector2(800, 600)
const PLAYER_SIZE := 24.0
const PLAYER_SPEED := 240.0
const COIN_RADIUS := 12.0
const OBSTACLE_SIZE := 24.0
const OBSTACLE_SPEED := 160.0
const OBSTACLE_INTERVAL := 2.0
const ROUND_DURATION := 30.0
const SAMPLE_INTERVAL := 0.5

enum State { PLAYING, ENDED }

var logger := EventLogger.new()
var state := State.PLAYING

var t := 0.0
var player_pos := ARENA / 2.0
var coin_pos := Vector2.ZERO
var coin_spawn_t := 0.0
var obstacles: Array[Dictionary] = []
var next_sample_t := SAMPLE_INTERVAL
var next_obstacle_t := OBSTACLE_INTERVAL

var coins_collected := 0
var obstacles_spawned := 0
var position_samples := 0
var died := false


func _ready() -> void:
	logger.log_event("session_start")
	_start_round()


func _process(delta: float) -> void:
	_step(delta, _read_direction())
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


func _read_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	return dir


func _start_round() -> void:
	t = 0.0
	player_pos = ARENA / 2.0
	obstacles.clear()
	next_sample_t = SAMPLE_INTERVAL
	next_obstacle_t = OBSTACLE_INTERVAL
	coins_collected = 0
	obstacles_spawned = 0
	position_samples = 0
	died = false
	state = State.PLAYING
	logger.new_round()
	logger.log_event("round_start", {"t": 0.0})
	_spawn_coin()


## Advances the simulation by `delta` seconds. Kept free of input reads so it can be driven by tests.
func _step(delta: float, dir: Vector2) -> void:
	if state != State.PLAYING:
		return
	t += delta

	var half := PLAYER_SIZE / 2.0
	player_pos += dir.normalized() * PLAYER_SPEED * delta
	player_pos = player_pos.clamp(Vector2(half, half), ARENA - Vector2(half, half))

	while t >= next_sample_t and next_sample_t <= ROUND_DURATION:
		position_samples += 1
		logger.log_event("player_position", {"t": _r(next_sample_t, 0.001), "x": _r(player_pos.x), "y": _r(player_pos.y)})
		next_sample_t += SAMPLE_INTERVAL

	while t >= next_obstacle_t and next_obstacle_t < ROUND_DURATION:
		_spawn_obstacle()
		next_obstacle_t += OBSTACLE_INTERVAL

	for o in obstacles:
		o.pos += o.vel * delta
	obstacles = obstacles.filter(func(o): return o.pos.x > -2.0 * OBSTACLE_SIZE and o.pos.x < ARENA.x + 2.0 * OBSTACLE_SIZE \
			and o.pos.y > -2.0 * OBSTACLE_SIZE and o.pos.y < ARENA.y + 2.0 * OBSTACLE_SIZE)

	if _circle_hits_player(coin_pos, COIN_RADIUS):
		coins_collected += 1
		logger.log_event("coin_collect", {"t": _r(t, 0.001), "x": _r(coin_pos.x), "y": _r(coin_pos.y), "dt": _r(t - coin_spawn_t, 0.001)})
		_spawn_coin()

	for o in obstacles:
		if _obstacle_hits_player(o.pos):
			died = true
			logger.log_event("player_death", {"t": _r(t, 0.001), "x": _r(player_pos.x), "y": _r(player_pos.y)})
			_end_round()
			return

	if t >= ROUND_DURATION:
		t = ROUND_DURATION
		_end_round()


func _end_round() -> void:
	state = State.ENDED
	logger.log_event("round_end", {
		"t": _r(t, 0.001),
		"coins_collected": coins_collected,
		"obstacles_spawned": obstacles_spawned,
		"position_samples": position_samples,
		"duration_s": _r(t, 0.001),
	})
	logger.close_round()


func _spawn_coin() -> void:
	var margin := COIN_RADIUS + 8.0
	coin_pos = Vector2(randf_range(margin, ARENA.x - margin), randf_range(margin, ARENA.y - margin))
	coin_spawn_t = t
	logger.log_event("coin_spawn", {"t": _r(t, 0.001), "x": _r(coin_pos.x), "y": _r(coin_pos.y)})


func _spawn_obstacle() -> void:
	var pos: Vector2
	var vel: Vector2
	match randi() % 4:
		0:
			pos = Vector2(-OBSTACLE_SIZE, randf_range(0.0, ARENA.y))
			vel = Vector2(OBSTACLE_SPEED, 0.0)
		1:
			pos = Vector2(ARENA.x + OBSTACLE_SIZE, randf_range(0.0, ARENA.y))
			vel = Vector2(-OBSTACLE_SPEED, 0.0)
		2:
			pos = Vector2(randf_range(0.0, ARENA.x), -OBSTACLE_SIZE)
			vel = Vector2(0.0, OBSTACLE_SPEED)
		_:
			pos = Vector2(randf_range(0.0, ARENA.x), ARENA.y + OBSTACLE_SIZE)
			vel = Vector2(0.0, -OBSTACLE_SPEED)
	obstacles.append({"pos": pos, "vel": vel})
	obstacles_spawned += 1


func _circle_hits_player(center: Vector2, radius: float) -> bool:
	var half := Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0
	var closest := center.clamp(player_pos - half, player_pos + half)
	return closest.distance_to(center) <= radius


func _obstacle_hits_player(pos: Vector2) -> bool:
	var half := Vector2(PLAYER_SIZE, PLAYER_SIZE) / 2.0
	var oh := Vector2(OBSTACLE_SIZE, OBSTACLE_SIZE) / 2.0
	return Rect2(player_pos - half, half * 2.0).intersects(Rect2(pos - oh, oh * 2.0))


func _r(value: float, step: float = 0.1) -> float:
	return snappedf(value, step)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ARENA), Color(0.1, 0.1, 0.14))
	draw_circle(coin_pos, COIN_RADIUS, Color(1.0, 0.82, 0.2))
	for o in obstacles:
		draw_rect(Rect2(o.pos - Vector2(OBSTACLE_SIZE, OBSTACLE_SIZE) / 2.0, Vector2(OBSTACLE_SIZE, OBSTACLE_SIZE)), Color(0.9, 0.2, 0.2))
	var half := PLAYER_SIZE / 2.0
	draw_rect(Rect2(player_pos - Vector2(half, half), Vector2(PLAYER_SIZE, PLAYER_SIZE)), Color(0.3, 0.8, 1.0))

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, 28), "Coins: %d   Time: %.1f" % [coins_collected, maxf(ROUND_DURATION - t, 0.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	if state == State.ENDED:
		var title := "You died" if died else "Time's up"
		draw_string(font, Vector2(0, 270), title, HORIZONTAL_ALIGNMENT_CENTER, ARENA.x, 40)
		draw_string(font, Vector2(0, 320), "Coins: %d" % coins_collected, HORIZONTAL_ALIGNMENT_CENTER, ARENA.x, 28)
		draw_string(font, Vector2(0, 370), "Press Enter to play again", HORIZONTAL_ALIGNMENT_CENTER, ARENA.x, 22)
