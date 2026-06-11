extends Control

## Start screen: New Game / Controls / Quit. Kept deliberately spartan —
## a dark ops-room title card.

const GAME_SCENE := "res://scenes/game.tscn"

var _controls: ControlsOverlay

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = "WARROOM"
	title.add_theme_font_size_override("font_size", 84)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "one week per turn  •  hold the line  •  mind the supplies"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(spacer)

	_menu_button(vbox, "New Game", func(): get_tree().change_scene_to_file(GAME_SCENE))
	_menu_button(vbox, "Controls", func(): _controls.toggle())
	if not OS.has_feature("web"):   # browsers don't quit
		_menu_button(vbox, "Quit", func(): get_tree().quit())

	var version := Label.new()
	version.text = Events.VERSION
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 12
	version.offset_top = -32
	version.modulate = Color(1, 1, 1, 0.45)
	version.add_theme_font_size_override("font_size", 13)
	add_child(version)

	_controls = ControlsOverlay.new()
	add_child(_controls)

func _menu_button(parent: Node, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	parent.add_child(b)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H and _controls != null:
			_controls.toggle()
		elif event.keycode == KEY_ESCAPE and _controls != null and _controls.visible:
			_controls.dismiss()
