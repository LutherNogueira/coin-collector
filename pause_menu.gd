class_name PauseMenu
extends CanvasLayer
## The Esc menu. It pauses the game (the round clock and the event log stop with it), lets the player pick a
## character, and opens the statistics screen over it. It keeps running while the rest of the tree is paused.

signal avatar_selected(avatar: String)
signal telemetry_changed(enabled: bool)

const PANEL_BG := Color(0.13, 0.16, 0.26)
const PANEL_BORDER := Color(0.28, 0.34, 0.52)
const TEXT := Color(0.93, 0.95, 1.0)
const MUTED := Color(0.62, 0.68, 0.82)
const GOLD := Color(1.0, 0.82, 0.2)

var avatar := Avatars.DEFAULT
var stats := StatsScreen.new()

var _resume_button: Button
var _character_button: Button
var _stats_button: Button
var _privacy_button: Button
var _preview: AnimatedSprite2D


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS   # so it works while the game is paused
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(340, 0)
	panel.add_child(column)
	column.add_child(_label("Paused", 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	_resume_button = _button("Resume  (Esc)")
	_resume_button.pressed.connect(close)
	column.add_child(_resume_button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var holder := Control.new()   # the animated preview of the chosen character
	holder.custom_minimum_size = Vector2(72, 72)
	_preview = AnimatedSprite2D.new()
	_preview.position = Vector2(36, 40)
	_preview.scale = Vector2(2, 2)
	holder.add_child(_preview)
	row.add_child(holder)
	var choice := VBoxContainer.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_button = _button("")
	_character_button.pressed.connect(func() -> void: cycle_avatar(1))
	_character_button.gui_input.connect(_on_character_input)
	choice.add_child(_character_button)
	choice.add_child(_label("Left / Right to change", 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(choice)
	column.add_child(row)

	_stats_button = _button("Statistics")
	_stats_button.pressed.connect(open_statistics)
	column.add_child(_stats_button)
	if EventSender.is_available():   # nothing is sent outside the web build, so there is nothing to switch
		_privacy_button = _button("")
		_privacy_button.pressed.connect(toggle_telemetry)
		column.add_child(_privacy_button)
		column.add_child(_label("Anonymous match statistics help the developer see how the game is played.", 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		_show_privacy()
	column.add_child(_label("M mutes the sound   |   F1 shows the hitboxes", 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	add_child(stats)
	stats.closed.connect(func() -> void: _stats_button.grab_focus())
	_show_avatar()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if stats.is_open():
			stats.close()   # Esc steps back one level: first the statistics, then the menu
		else:
			toggle()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


## Picks the avatar `step` places along the list; the choice is saved and announced.
func cycle_avatar(step: int) -> void:
	set_avatar(Avatars.shifted(avatar, step), true)


func set_avatar(new_avatar: String, announce: bool = false) -> void:
	avatar = Avatars.valid(new_avatar)
	_show_avatar()
	if announce:
		Settings.save_avatar(avatar)
		avatar_selected.emit(avatar)


func open_statistics() -> void:
	stats.open(avatar)


## Switches the anonymous statistics on or off and remembers it.
func toggle_telemetry() -> void:
	var enabled := not Settings.load_telemetry()
	Settings.save_telemetry(enabled)
	telemetry_changed.emit(enabled)
	_show_privacy()


func _show_privacy() -> void:
	if _privacy_button != null:
		_privacy_button.text = "Send anonymous statistics: %s" % ("on" if Settings.load_telemetry() else "off")


func _show_avatar() -> void:
	if _character_button == null:
		return
	_character_button.text = "< %s >" % Avatars.display_name(avatar)
	_preview.sprite_frames = PlayerView.frames_for(avatar)
	_preview.play("idle")


func _on_character_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			cycle_avatar(-1)
			_character_button.accept_event()
		elif event.keycode == KEY_RIGHT:
			cycle_avatar(1)
			_character_button.accept_event()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(0, 40)
	return button


func _label(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
