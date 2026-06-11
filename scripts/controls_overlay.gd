class_name ControlsOverlay
extends Control

## "How to play" + controls reference. Used by both the main menu and the
## in-game UI (H key). Self-contained: builds everything in code.

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # shields the board
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.97)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "WARROOM — FIELD MANUAL"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	vbox.add_child(columns)

	var how := RichTextLabel.new()
	how.bbcode_enabled = true
	how.fit_content = true
	how.custom_minimum_size = Vector2(390, 0)
	how.text = """[b]HOW TO PLAY[/b]

You command the green army from the map table. Each turn is one week: give your divisions their orders, then press [b]End Turn[/b].

[b]•[/b] A card arrives each week — [color=#73bfff]intel[/color] informs, [color=#ffa64d]events[/color] happen, [color=#ff7373]decisions[/color] must be answered before the next turn.
[b]•[/b] Your capital generates supplies; towns barely do. Haul stock forward with engineers and trains — units refill from [i]adjacent[/i] friendly cities, engineers and trains.
[b]•[/b] Watch the [color=#ff7373]red arrows[/color]: every attack is telegraphed one week ahead. No arrow, no hit.
[b]•[/b] Artillery must [b]set up (D)[/b] before it can fire. Moving packs it up.
[b]•[/b] Divisions tire after ~12 weeks in the field — [b]Garrison[/b] them in a city to rest. If that city falls, they're lost with it.
[b]•[/b] Retreating from contact draws withdrawal fire. Cut-off ground starves.

[b]Win[/b] by taking the enemy capital — or by destroying the coalition expedition when it lands. [b]Lose[/b] your capital and the war is over."""
	columns.add_child(how)

	var keys := RichTextLabel.new()
	keys.bbcode_enabled = true
	keys.fit_content = true
	keys.custom_minimum_size = Vector2(370, 0)
	keys.text = """[b]ORDERS[/b]
[b]Left click[/b] — select / order (move, attack, transfer supplies)
[b]Click destination[/b] — set or replace a move order
[b]Shift + click[/b] — add exact waypoints
[b]Click selected unit[/b] — cancel its orders
[b]Right click / Esc[/b] — deselect
[b]M / F[/b] — clear movement / clear target
[b]D[/b] — artillery: set up / pack up

[b]RAIL & SUPPLY[/b]
[b]R[/b] — plan rail on hovered hex (engineers must be adjacent)
[b]T[/b] — commit or extend the rail line (new lines need a train)
Panel buttons — [b]Garrison[/b], [b]Deliver[/b], [b]Set Route[/b] (standing supply run)
Click a rail hex with a train selected to drive it

[b]OTHER[/b]
[b]C[/b] — cycle territory overlay
[b]H[/b] — this manual
Click a unit's name to rename it"""
	columns.add_child(keys)

	var close := Button.new()
	close.text = "Close  (H)"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(dismiss)
	vbox.add_child(close)

	hide()

func dismiss() -> void:
	hide()
	closed.emit()

func toggle() -> void:
	if visible:
		dismiss()
	else:
		show()
