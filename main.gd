extends Node2D

const COIN_RADIUS := 12.0
const SAMPLE_INTERVAL := 0.5
## Seconds between a death and the player reappearing at the start. The round clock keeps running.
const DEATH_DELAY := 0.6
const NOTICE_SECONDS := 12.0

enum State { PLAYING, DYING, ENDED }

var logger := EventLogger.new()
var sender := EventSender.new()
## Seconds left of the first-visit notice about anonymous statistics.
var notice_left := 0.0
var state := State.PLAYING

var level: Level
var body: PlatformPhysics.Body
var level_view: LevelView
var view: PlayerView
var hud: Node2D
var menu: PauseMenu
var touch := TouchControls.new()
var sfx: Sfx
var show_hitbox := false
var t := 0.0
var next_sample_t := SAMPLE_INTERVAL
var respawn_timer := 0.0
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
	# Child order is draw order: background, level, player, then the HUD on top.
	add_child(ScrollingBackground.new())
	add_child(Music.new())
	sfx = Sfx.new()
	add_child(sfx)
	level_view = LevelView.new()
	add_child(level_view)
	view = PlayerView.new()
	add_child(view)
	hud = Node2D.new()
	hud.draw.connect(_draw_hud)
	add_child(hud)
	menu = PauseMenu.new()
	menu.avatar_selected.connect(view.set_avatar)
	menu.telemetry_changed.connect(sender.set_enabled)
	add_child(menu)
	var saved_avatar := Settings.load_avatar()
	view.set_avatar(saved_avatar)
	menu.set_avatar(saved_avatar)
	# Sending (web build only) is wired before the first event so session_start is included.
	sender.start(Settings.load_telemetry())
	logger.sink = sender.push
	if EventSender.is_available() and not Settings.notice_seen():
		notice_left = NOTICE_SECONDS
		Settings.mark_notice_seen()
	_center_arena()
	get_viewport().size_changed.connect(_center_arena)
	touch.forced = touch.forced or TouchControls.requested_by_page()
	touch.pressed.connect(_on_touch_pressed)
	add_child(touch)
	logger.log_event("session_start")
	_start_round()
	view.sync_with(body, 0.0)   # so the player is already in place if the menu is opened on the first frame


func _process(delta: float) -> void:
	var jump_down := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or touch.jump_down()
	var move_x := _read_move_x()
	_step(delta, move_x, jump_down and not jump_was_down)
	jump_was_down = jump_down
	notice_left = maxf(notice_left - delta, 0.0)
	view.sync_with(body, move_x)
	hud.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		show_hitbox = not show_hitbox   # debug: outline of the collision box
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		sfx.toggle_mute()
	if state == State.ENDED and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_start_round()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state != State.ENDED:
			_end_round()
		logger.log_event("session_end")


func _read_move_x() -> float:
	var x := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		x += 1.0
	return clampf(x + touch.move_x(), -1.0, 1.0)


## The window can be wider or taller than the 800x600 arena (stretch aspect is "expand"); keep the arena in the middle
## and leave the rest for the touch buttons.
func _center_arena() -> void:
	position = ((get_viewport().get_visible_rect().size - Level.ARENA) / 2.0).floor()


## After a win, a tap anywhere starts the next level (the touch version of pressing Enter).
func _on_touch_pressed(_position: Vector2) -> void:
	if state == State.ENDED:
		_start_round()


## The first round of a session plays the hand-made level (seed 0); later rounds get a random seed.
func _start_round() -> void:
	if state != State.ENDED and logger.round_id != null:
		_end_round()
	var level_seed := 0 if rounds_started == 0 else randi_range(1, 2147483647)
	rounds_started += 1
	level = Level.hand_made() if level_seed == 0 else Level.generate(level_seed)
	level_view.show_level(level)
	t = 0.0
	next_sample_t = SAMPLE_INTERVAL
	coins_collected = 0
	deaths = 0
	jumps = 0
	position_samples = 0
	completed = false
	state = State.PLAYING
	view.visible = true
	logger.new_round()
	logger.log_event("round_start", {"t": 0.0, "level_seed": level_seed, "generator_version": Level.GENERATOR_VERSION})
	_reset_level()


## Puts the player back at the start and restores every coin.
func _reset_level() -> void:
	body = PlatformPhysics.Body.new(Level.START_POS)
	level_view.restore_coins()
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
	while remaining > 0.0 and state != State.ENDED:
		var h := minf(remaining, PlatformPhysics.SUBSTEP)
		remaining -= h
		if state == State.DYING:
			_dying_substep(h)
		else:
			_substep(h, move_x, jump)
		jump = false


## The player is dead: nothing moves or is recorded until the delay is over.
func _dying_substep(h: float) -> void:
	t += h
	respawn_timer -= h
	if respawn_timer <= 0.0:
		_respawn()


func _respawn() -> void:
	_reset_level()
	logger.log_event("player_respawn", _pos_payload())
	next_sample_t = (floorf(t / SAMPLE_INTERVAL) + 1.0) * SAMPLE_INTERVAL   # no samples for the time spent dead
	view.visible = true
	state = State.PLAYING


func _substep(h: float, move_x: float, jump_pressed: bool) -> void:
	t += h
	var result := PlatformPhysics.step(body, level, h, move_x, jump_pressed)
	if result["jumped"]:
		jumps += 1
		sfx.play("jump")
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
			level_view.collect(i)
			sfx.play("collect")
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
		view.show_hit_at(self, body)
		view.visible = false
		sfx.play("death")
		respawn_timer = DEATH_DELAY
		state = State.DYING
		return

	if not collected.has(false):
		completed = true
		sfx.play("win")
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


## Text and debug outlines, drawn by the `hud` node so they sit above the level and the player.
func _draw_hud() -> void:
	if show_hitbox:
		hud.draw_rect(body.rect(), Color(0.3, 0.8, 1.0, 0.35))
		for trap: Rect2 in level.traps:
			hud.draw_rect(Level.trap_hitbox(trap), Color(1.0, 0.3, 0.3, 0.35), false)
		for coin: Vector2 in level.coins:
			hud.draw_arc(coin, COIN_RADIUS, 0.0, TAU, 24, Color(1.0, 0.9, 0.3, 0.6))

	_hud_text(Vector2(12, 28), "Coins: %d/%d   Deaths: %d" % [collected.count(true), level.coins.size(), deaths], 22)
	_hud_text(Vector2(12, Level.ARENA.y - 12), "Level %s   (Esc menu, M mute, F1 hitboxes)" % ("0 (hand-made)" if level.seed_value == 0 else str(level.seed_value)), 14)
	if notice_left > 0.0:
		_hud_text(Vector2(0, 56), "This game sends anonymous match statistics to its developer.", 14, HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x)
		_hud_text(Vector2(0, 76), "You can turn that off in the Esc menu.", 14, HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x)
	if state == State.ENDED:
		_hud_text(Vector2(0, 220), "Level complete!", 40, HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x)
		_hud_text(Vector2(0, 270), "Time: %.1f s   Deaths: %d" % [t, deaths], 26, HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x)
		_hud_text(Vector2(0, 315), "Tap for a new level" if touch.is_active() else "Press Enter for a new level", 22, HORIZONTAL_ALIGNMENT_CENTER, Level.ARENA.x)


func _hud_text(pos: Vector2, text: String, size: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var font := ThemeDB.fallback_font
	hud.draw_string_outline(font, pos, text, align, width, size, 6, Color(0.08, 0.1, 0.18))
	hud.draw_string(font, pos, text, align, width, size)
