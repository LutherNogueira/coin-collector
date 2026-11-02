class_name ScrollingBackground
extends Sprite2D
## Tiles the 64 px background texture over the whole screen and drifts it slowly. Purely visual.

const TILE := 64.0
const DRIFT := Vector2(10.0, 10.0)   # px per second

var _offset := Vector2.ZERO


func _init() -> void:
	texture = load("res://assets/background/blue.png")
	centered = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	region_enabled = true
	self_modulate = Color(0.78, 0.84, 0.95)   # a little darker, so the foreground stands out
	region_rect = Rect2(Vector2.ZERO, Level.ARENA)


func _process(delta: float) -> void:
	_offset = Vector2(fposmod(_offset.x + DRIFT.x * delta, TILE), fposmod(_offset.y + DRIFT.y * delta, TILE))
	region_rect = Rect2(_offset, Level.ARENA)
