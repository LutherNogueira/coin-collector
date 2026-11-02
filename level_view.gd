class_name LevelView
extends Node2D
## Draws a Level with the Pixel Adventure art: grass-topped terrain tiles, spike tiles and animated fruit coins.
## Purely visual: collisions and coin pickup still use the Level's rectangles and circles.

const TILE := 16
## Top-left corner of the 3x3 grass block inside terrain.png (corners, edges and centre).
const GRASS_ORIGIN := Vector2i(96, 0)
const FRUIT_DIR := "res://assets/items/fruits/"
const FRUITS := ["apple", "bananas", "cherries", "kiwi", "melon", "orange", "pineapple", "strawberry"]
const FRUIT_FRAME := 32
const FPS := 20.0

static var _frames: SpriteFrames

var level: Level
var _terrain: Texture2D = load("res://assets/terrain/terrain.png")
var _spikes: Texture2D = load("res://assets/terrain/spikes.png")
var _coin_sprites: Array[AnimatedSprite2D] = []


func show_level(new_level: Level) -> void:
	level = new_level
	for sprite in _coin_sprites:
		sprite.queue_free()
	_coin_sprites.clear()
	for i in level.coins.size():
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = _shared_frames()
		sprite.position = level.coins[i]
		sprite.play(FRUITS[i % FRUITS.size()])
		sprite.frame = (i * 5) % 17   # offset so the fruits do not bob in sync
		add_child(sprite)
		_coin_sprites.append(sprite)
	queue_redraw()


## Brings every coin back (the level restarts after a death).
func restore_coins() -> void:
	for sprite in _coin_sprites:
		sprite.visible = true


## Hides coin `index` and plays the "collected" burst where it was.
func collect(index: int) -> void:
	_coin_sprites[index].visible = false
	var burst := AnimatedSprite2D.new()
	burst.sprite_frames = _shared_frames()
	burst.position = level.coins[index]
	burst.animation_finished.connect(burst.queue_free)
	add_child(burst)
	burst.play("collected")


func _draw() -> void:
	if level == null:
		return
	for solid: Rect2 in level.solids:
		_draw_terrain(solid)
	for trap: Rect2 in level.traps:
		for i in ceili(trap.size.x / TILE):
			draw_texture(_spikes, trap.position + Vector2(i * TILE, 0))


## Fills a solid with the 3x3 grass block: grass on the top row, outlines on the outer tiles.
func _draw_terrain(solid: Rect2) -> void:
	var cols := ceili(solid.size.x / TILE)
	var rows := ceili(solid.size.y / TILE)
	for row in rows:
		var tile_row := 0 if row == 0 else (2 if row == rows - 1 else 1)
		for col in cols:
			var tile_col := 0 if col == 0 else (2 if col == cols - 1 else 1)
			var source := Rect2(GRASS_ORIGIN + Vector2i(tile_col, tile_row) * TILE, Vector2(TILE, TILE))
			draw_texture_rect_region(_terrain, Rect2(solid.position + Vector2(col, row) * TILE, Vector2(TILE, TILE)), source)


static func _shared_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	_frames = SpriteFrames.new()
	_frames.remove_animation("default")
	for fruit in FRUITS:
		_add_strip(fruit, FRUIT_DIR + fruit + ".png", true)
	_add_strip("collected", FRUIT_DIR + "collected.png", false)
	return _frames


static func _add_strip(animation: String, path: String, loop: bool) -> void:
	var sheet: Texture2D = load(path)
	_frames.add_animation(animation)
	_frames.set_animation_speed(animation, FPS)
	_frames.set_animation_loop(animation, loop)
	for i in sheet.get_width() / FRUIT_FRAME:
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(i * FRUIT_FRAME, 0, FRUIT_FRAME, FRUIT_FRAME)
		_frames.add_frame(animation, frame)
