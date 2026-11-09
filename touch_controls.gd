class_name TouchControls
extends CanvasLayer
## Touch controls drawn over the game: an analog stick that appears under the left thumb, a jump zone on the right
## half of the screen and a menu button in the top right corner (the same as pressing Esc).
## Every finger is tracked on its own, so the stick and the jump work at the same time. They only show on a touch
## screen, or when forced (add ?touch to the page address to try them with a mouse).

## A finger went down at this point (not on the menu button); used to start the next level after a win.
signal pressed(position: Vector2)
## The menu button was tapped.
signal menu_requested

const STICK_RADIUS := 70.0      # how far the knob can travel from where the thumb first touched
const DEAD_ZONE := 0.15         # share of the radius that still counts as standing still
const MARGIN := 16.0
const JUMP_RADIUS := 52.0
const MENU_SIZE := Vector2(52, 52)
## Fingers are not precise: a press just outside the menu button still counts.
const SLACK := 10.0
const MOUSE_FINGER := -1
const NO_FINGER := -99

enum Role { NONE, STICK, JUMP, MENU }

## Show the controls even without a touch screen (tests, or ?touch in the page address).
var forced := false

var _roles := {}   # finger index -> Role
var _stick_finger := NO_FINGER
var _stick_origin := Vector2.ZERO
var _stick_now := Vector2.ZERO
var _canvas := Node2D.new()


## True when the page address asks for the controls (web build only).
static func requested_by_page() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('touch')"))


func _init() -> void:
	layer = 5


func _ready() -> void:
	get_viewport().size_changed.connect(_canvas.queue_redraw)
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	visible = is_active()


func is_active() -> bool:
	return forced or DisplayServer.is_touchscreen_available()


## Horizontal push of the stick from -1 (full left) to 1 (full right), 0 inside the dead zone.
func move_x() -> float:
	if _stick_finger == NO_FINGER:
		return 0.0
	var pull := clampf((_stick_now.x - _stick_origin.x) / STICK_RADIUS, -1.0, 1.0)
	if absf(pull) < DEAD_ZONE:
		return 0.0
	return signf(pull) * (absf(pull) - DEAD_ZONE) / (1.0 - DEAD_ZONE)


func jump_down() -> bool:
	return _roles.values().has(Role.JUMP)


func stick_active() -> bool:
	return _stick_finger != NO_FINGER


## Lets go of every finger (the game does this when the menu opens, so nothing stays held while it is paused).
func release_all() -> void:
	_roles.clear()
	_stick_finger = NO_FINGER
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif forced and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(MOUSE_FINGER, event.position, event.pressed)
	elif forced and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag(MOUSE_FINGER, event.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()   # a finger lifted while the window was away would otherwise leave the stick stuck


func _touch(index: int, position: Vector2, down: bool) -> void:
	if down:
		var role := role_at(position)
		if role == Role.STICK and _stick_finger != NO_FINGER:
			role = Role.NONE   # the stick already has a thumb on it
		_roles[index] = role
		match role:
			Role.STICK:
				_stick_finger = index
				_stick_origin = position
				_stick_now = position
			Role.MENU:
				menu_requested.emit()
		if role != Role.MENU:
			pressed.emit(position)
	else:
		if index == _stick_finger:
			_stick_finger = NO_FINGER
		_roles.erase(index)
	_canvas.queue_redraw()


func _drag(index: int, position: Vector2) -> void:
	if index == _stick_finger:
		_stick_now = position
		_canvas.queue_redraw()


## What a finger that goes down at `point` is for: the menu button, the stick (left half) or the jump (right half).
func role_at(point: Vector2) -> int:
	if menu_rect().grow(SLACK).has_point(point):
		return Role.MENU
	return Role.STICK if point.x < _screen().x / 2.0 else Role.JUMP


func menu_rect() -> Rect2:
	return Rect2(Vector2(_screen().x - MARGIN - MENU_SIZE.x, MARGIN), MENU_SIZE)


## Where the stick rests, and where the jump hint is drawn, before any finger moves them.
func rest_position() -> Vector2:
	var s := _screen()
	return Vector2(MARGIN + STICK_RADIUS + 14.0, s.y - MARGIN - STICK_RADIUS - 14.0)


func jump_position() -> Vector2:
	var s := _screen()
	return Vector2(s.x - MARGIN - JUMP_RADIUS - 14.0, s.y - MARGIN - JUMP_RADIUS - 14.0)


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _draw_controls() -> void:
	# Stick: faint at its resting place, under the thumb while held.
	var held := stick_active()
	var base := _stick_origin if held else rest_position()
	var knob := base
	if held:
		knob = base + (_stick_now - base).limit_length(STICK_RADIUS)
	_canvas.draw_circle(base, STICK_RADIUS, Color(0.05, 0.08, 0.16, 0.38 if held else 0.18))
	_canvas.draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.6 if held else 0.3), 3.0)
	_canvas.draw_circle(knob, 28.0, Color(1, 1, 1, 0.65 if held else 0.3))

	# Jump: a hint at the bottom right; the whole right half of the screen is the button.
	var jumping := jump_down()
	var jc := jump_position()
	_canvas.draw_circle(jc, JUMP_RADIUS, Color(0.05, 0.08, 0.16, 0.45 if jumping else 0.18))
	_canvas.draw_arc(jc, JUMP_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.75 if jumping else 0.35), 3.0)
	var s := 20.0
	_canvas.draw_colored_polygon(
		PackedVector2Array([jc + Vector2(0, -s), jc + Vector2(-s, s * 0.7), jc + Vector2(s, s * 0.7)]),
		Color(1, 1, 1, 0.9 if jumping else 0.4))

	# Menu button: two bars (pause).
	var m := menu_rect()
	_canvas.draw_rect(m, Color(0.05, 0.08, 0.16, 0.4))
	_canvas.draw_rect(m, Color(1, 1, 1, 0.55), false, 3.0)
	var c := m.get_center()
	_canvas.draw_rect(Rect2(c + Vector2(-11, -13), Vector2(8, 26)), Color(1, 1, 1, 0.8))
	_canvas.draw_rect(Rect2(c + Vector2(3, -13), Vector2(8, 26)), Color(1, 1, 1, 0.8))
