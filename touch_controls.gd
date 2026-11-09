class_name TouchControls
extends CanvasLayer
## On-screen buttons for phones and tablets: left and right at the bottom left, jump at the bottom right.
## Each finger is tracked on its own, so a player can hold a direction and tap jump at once, and sliding a finger
## from one button to the other changes direction. They only show on a touch screen, or when forced
## (add ?touch to the page address to try them with a mouse).

## A finger went down at this point (used to start the next level after a win).
signal pressed(position: Vector2)

const BUTTON_SIZE := Vector2(100, 100)
const MARGIN := 16.0
const GAP := 12.0
## Fingers are not precise: a press just outside a button still counts.
const SLACK := 18.0
const MOUSE_FINGER := -1
const NAMES := ["left", "right", "jump"]

## Show the buttons even without a touch screen (tests, or ?touch in the page address).
var forced := false

var _fingers := {}   # finger index -> name of the button under it ("" when none)
var _canvas := Node2D.new()


## True when the page address asks for the buttons (web build only).
static func requested_by_page() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('touch')"))


func _init() -> void:
	layer = 5


func _ready() -> void:
	get_viewport().size_changed.connect(_canvas.queue_redraw)   # the buttons follow the screen's corners
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	visible = is_active()


func is_active() -> bool:
	return forced or DisplayServer.is_touchscreen_available()


## -1 while only left is held, +1 while only right is held, otherwise 0.
func move_x() -> float:
	return float(int(is_held("right")) - int(is_held("left")))


func jump_down() -> bool:
	return is_held("jump")


func is_held(button: String) -> bool:
	return _fingers.values().has(button)


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_fingers[event.index] = button_at(event.position)
		_canvas.queue_redraw()
	elif forced and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(MOUSE_FINGER, event.position, event.pressed)
	elif forced and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_fingers[MOUSE_FINGER] = button_at(event.position)
		_canvas.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_fingers.clear()   # a finger lifted while the window was away would otherwise leave a button stuck
		_canvas.queue_redraw()


func _touch(index: int, position: Vector2, down: bool) -> void:
	if down:
		_fingers[index] = button_at(position)
		pressed.emit(position)
	else:
		_fingers.erase(index)
	_canvas.queue_redraw()


## Where a button is, in viewport coordinates. They sit in the bottom corners of the whole screen (the game is
## centred, so on a phone that is the free space beside it, or below it when held upright).
func button_rect(button: String) -> Rect2:
	var screen := get_viewport().get_visible_rect().size
	var y := screen.y - MARGIN - BUTTON_SIZE.y
	match button:
		"left": return Rect2(Vector2(MARGIN, y), BUTTON_SIZE)
		"right": return Rect2(Vector2(MARGIN + BUTTON_SIZE.x + GAP, y), BUTTON_SIZE)
		_: return Rect2(Vector2(screen.x - MARGIN - BUTTON_SIZE.x, y), BUTTON_SIZE)


## The button under a point, or "" when there is none.
func button_at(point: Vector2) -> String:
	for name: String in NAMES:
		if button_rect(name).grow(SLACK).has_point(point):
			return name
	return ""


func _draw_buttons() -> void:
	for name: String in NAMES:
		var rect := button_rect(name)
		var held := is_held(name)
		_canvas.draw_rect(rect, Color(0.05, 0.08, 0.16, 0.55 if held else 0.3))
		_canvas.draw_rect(rect, Color(1, 1, 1, 0.75 if held else 0.45), false, 3.0)
		var c := rect.get_center()
		var s := 24.0
		var arrow := PackedVector2Array()
		match name:
			"left": arrow = [c + Vector2(-s, 0), c + Vector2(s * 0.6, -s), c + Vector2(s * 0.6, s)]
			"right": arrow = [c + Vector2(s, 0), c + Vector2(-s * 0.6, -s), c + Vector2(-s * 0.6, s)]
			"jump": arrow = [c + Vector2(0, -s), c + Vector2(-s, s * 0.6), c + Vector2(s, s * 0.6)]
		_canvas.draw_colored_polygon(arrow, Color(1, 1, 1, 0.9 if held else 0.6))
