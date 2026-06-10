extends CanvasLayer
class_name UIManager

## All HUD: top bar (date/season/weather), unit/city stats panel, card display,
## stock readout, toasts, game-over screen, and the debug overlay (F3).
## Talks back to gameplay only through signals — it never drives systems itself.

signal next_day_requested
signal card_choice_made(card_data: Dictionary, choice: String)

# ── Scene references ──────────────────────────────────────────────────────────
@onready var daycounter: Label = $DayCount
@onready var nextdaybutton: Button = $NextDay
@onready var panel: Panel = $Panel
@onready var lbl_name: Label = $Panel/VBoxContainer/Name
@onready var lbl_res: Label = $Panel/VBoxContainer/Resources
@onready var lbl_act: Label = $Panel/VBoxContainer/Action
@onready var lbl_mode: Label = $Panel/VBoxContainer/Mode
@onready var card_ui: CardUI = $CardUI

var s: GameServices

var current_viewed_piece: Node2D = null
var decision_pending: bool = false

# Runtime-built stats panel extras (FTL-style bars; numbers live in tooltips)
const RESOURCE_ICON = preload("res://assets/resource_icon.png")
const ATTACK_ICON = preload("res://assets/attack_icon.png")
const DRAIN_ICON = preload("res://assets/drain_icon.png")
const METER_ICONS := { "attack": ATTACK_ICON, "capacity": RESOURCE_ICON, "drain": DRAIN_ICON }
const SUPPLY_BAR_WIDTH := 170.0   # the headline bar
const BAR_WIDTH := 104.0          # veterancy meters

var supply_bar: ProgressBar = null
var meter_box: VBoxContainer = null

# Built-in-code UI
var top_bar: PanelContainer = null
var top_bar_lbl: Label = null
var stock_lbl: Label = null
var toast_box: VBoxContainer = null
var debug_lbl: Label = null

func setup(services: GameServices):
	s = services
	_build_top_bar()
	_build_stock_readout()
	_build_toast_box()
	_build_debug_overlay()
	_style_stats_panel()
	_build_stats_extras()
	panel.hide()
	card_ui.hide()
	nextdaybutton.pressed.connect(func(): next_day_requested.emit())

	if not card_ui.card_chosen.is_connected(_on_card_ui_choice_made):
		card_ui.card_chosen.connect(_on_card_ui_choice_made)

	Events.day_advanced.connect(func(_d): _refresh_top_bar())
	Events.weather_changed.connect(func(_w): _refresh_top_bar())
	Events.toast.connect(show_toast)
	Events.decision_pending.connect(set_decision_pending)

	_refresh_top_bar()
	_refresh_stock()

# ── Shared styling ────────────────────────────────────────────────────────────

func _hud_style(alpha := 0.85) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, alpha)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _style_stats_panel():
	panel.add_theme_stylebox_override("panel", _hud_style(0.92))

func _build_stats_extras():
	var vbox = lbl_res.get_parent()

	# Click the name to rename (player pieces only), FTL-style
	lbl_name.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl_name.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lbl_name.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var p = current_viewed_piece
			if p and is_instance_valid(p) and p.team == 1:
				_open_rename_dialog(p)
	)

	# Raw text line replaced by an icon + supply bar (hover for exact numbers)
	lbl_res.visible = false
	supply_bar = ProgressBar.new()
	supply_bar.custom_minimum_size = Vector2(SUPPLY_BAR_WIDTH, 14)
	supply_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	supply_bar.show_percentage = false
	supply_bar.mouse_filter = Control.MOUSE_FILTER_PASS   # allow tooltip
	_style_bar(supply_bar, Color(0.25, 0.75, 0.35))
	var supply_row := _icon_row(RESOURCE_ICON, supply_bar, 16)
	vbox.add_child(supply_row)
	vbox.move_child(supply_row, lbl_res.get_index() + 1)

	# Veterancy meters: thin colored bars, one per upgrade track
	meter_box = VBoxContainer.new()
	meter_box.add_theme_constant_override("separation", 3)
	vbox.add_child(meter_box)
	vbox.move_child(meter_box, supply_row.get_index() + 1)

	# Small action/mode text
	lbl_act.add_theme_font_size_override("font_size", 12)
	lbl_mode.add_theme_font_size_override("font_size", 12)
	lbl_mode.modulate = Color(1, 1, 1, 0.8)


func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.corner_radius_top_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", fill)

func _icon_row(texture: Texture2D, bar: ProgressBar, icon_size: int) -> HBoxContainer:
	## icon + bar side by side; hovering either shows the bar's tooltip.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(icon)
	row.add_child(bar)
	return row

func _set_meters(meters: Array) -> void:
	for c in meter_box.get_children():
		c.queue_free()
	for m in meters:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(BAR_WIDTH, 10)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.max_value = m["max"]
		bar.value = m["value"]
		bar.tooltip_text = m["tip"]
		_style_bar(bar, m["color"])
		var row := _icon_row(METER_ICONS.get(m.get("id", "capacity"), RESOURCE_ICON), bar, 14)
		var icon: TextureRect = row.get_child(0)
		icon.tooltip_text = m["tip"]
		meter_box.add_child(row)

func _open_rename_dialog(piece: Node2D):
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var overlay = PanelContainer.new()
	overlay.add_theme_stylebox_override("panel", _hud_style(0.96))
	center.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	overlay.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "Rename unit:"
	vbox.add_child(lbl)

	var edit = LineEdit.new()
	edit.text = str(piece.name)
	edit.custom_minimum_size = Vector2(260, 0)
	vbox.add_child(edit)

	var apply := func():
		# Strip characters Godot node names can't hold
		var n = edit.text.strip_edges()
		for bad in [".", "/", ":", "@", "\"", "%"]:
			n = n.replace(bad, "")
		if n != "" and is_instance_valid(piece):
			piece.name = n
			refresh_stats()
		center.queue_free()

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ok = Button.new()
	ok.text = "OK"
	ok.pressed.connect(apply)
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): center.queue_free())
	row.add_child(ok)
	row.add_child(cancel)
	vbox.add_child(row)

	edit.text_submitted.connect(func(_t): apply.call())
	add_child(center)
	edit.grab_focus()
	edit.select_all()

# ── Top bar (date / season / weather) ─────────────────────────────────────────

func _build_top_bar():
	top_bar = PanelContainer.new()
	top_bar.position.y = 8
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_stylebox_override("panel", _hud_style())

	top_bar_lbl = Label.new()
	top_bar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(top_bar_lbl)
	add_child(top_bar)

func _position_top_bar():
	## Keep the bar horizontally centred over the hex grid (not the window).
	if top_bar == null or s == null or s.grid == null: return
	var world: Vector2 = s.grid.base_layer.to_global(s.grid.get_hex_pos(Vector2i(0, 0)))
	var screen: Vector2 = s.grid.get_viewport().get_canvas_transform() * world
	top_bar.position.x = screen.x - top_bar.size.x * 0.5

func _refresh_top_bar():
	if top_bar_lbl == null or s == null: return
	var weather := s.weather.weather_name
	var weather_part := "" if weather == "clear" else "   •   %s" % weather.capitalize()
	top_bar_lbl.text = "Week %d   •   %s (%s)%s" % [
		s.turn.day, s.weather.date_string(), s.weather.current_season().capitalize(), weather_part
	]

# ── Stock readout (rails / trains / bridges / tunnels from cards) ─────────────

func _build_stock_readout():
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 12
	box.offset_top = -44
	box.offset_bottom = -12
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", _hud_style())

	stock_lbl = Label.new()
	stock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_lbl.add_theme_font_size_override("font_size", 13)
	box.add_child(stock_lbl)
	add_child(box)

func _refresh_stock():
	if stock_lbl == null or s == null: return
	stock_lbl.text = "Stock — rail: %d   trains: %d   bridges: %d   tunnels: %d" % [
		s.rail_network.player_rail_stock, s.rail_network.player_train_stock,
		s.terrain.bridge_stock, s.terrain.tunnel_stock
	]

func _process(_delta):
	# Stocks change from many places (cards, building, planning); cheap to poll.
	_refresh_stock()
	_position_top_bar()

# ── Toasts ────────────────────────────────────────────────────────────────────

func _build_toast_box():
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_box.offset_left = -250
	toast_box.offset_right = 250
	toast_box.offset_top = -200
	toast_box.offset_bottom = -80
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 4)
	add_child(toast_box)

func show_toast(message: String):
	var lbl := Label.new()
	lbl.text = message
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_stylebox_override("normal", _hud_style(0.9))
	toast_box.add_child(lbl)

	# Cap the stack so a noisy turn doesn't flood the screen
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).queue_free()

	var tween := lbl.create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tween.tween_callback(lbl.queue_free)

# ── Decision flow control ─────────────────────────────────────────────────────

func set_decision_pending(pending: bool):
	decision_pending = pending
	nextdaybutton.disabled = pending
	nextdaybutton.text = "Decision required" if pending else "End Turn"

# ── City picker (decision-card purchases) ─────────────────────────────────────

func show_city_picker(eligible_cities: Array, cost: int, on_pick: Callable):
	set_decision_pending(true)   # still mid-decision until a city is chosen

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var overlay = PanelContainer.new()
	overlay.add_theme_stylebox_override("panel", _hud_style(0.96))
	center.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	overlay.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "Select a city to pay %d resources:" % cost
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	for c in eligible_cities:
		var btn = Button.new()
		btn.text = "%s (%d resources)" % [c.name, c.get_resources()]
		btn.pressed.connect(func():
			on_pick.call(c)
			set_decision_pending(false)
			center.queue_free()
		)
		vbox.add_child(btn)

	add_child(center)

# ── Stats panel ───────────────────────────────────────────────────────────────

func show_stats(piece):
	current_viewed_piece = piece
	lbl_name.text = str(piece.name)

	# Supply bar — exact numbers on hover, FTL-style
	supply_bar.max_value = piece.get_max_resources()
	supply_bar.value = piece.get_resources()
	var supply_tip := "Supplies %d / %d" % [piece.get_resources(), piece.get_max_resources()]
	if piece is City:
		supply_tip += " — income %d/wk" % piece.resource_comp.replenish_rate
	else:
		supply_tip += " — drain %d/wk" % piece.resource_comp.deplete_rate
		if piece.is_combatant() and piece.attack_comp:
			supply_tip += ", damage %d (range %d)" % [piece.attack_comp.damage, piece.attack_comp.attack_range]
	supply_bar.tooltip_text = supply_tip
	supply_bar.get_parent().get_child(0).tooltip_text = supply_tip   # the icon too

	# Veterancy meters for the player's own units
	if piece is City or piece.team != 1:
		_set_meters([])
	else:
		_set_meters(piece.service_meters())
	lbl_name.tooltip_text = "Click to rename" if piece.team == 1 else ""

	if piece is City:
		var role := "Capital" if piece.is_capital else "Town"
		lbl_act.text = "%s — income %d/wk" % [role, piece.resource_comp.replenish_rate]
	else:
		lbl_act.text = "Action: %s" % ("Used" if piece.is_frozen() else "Ready")

	var move_comp = piece.get("movement_comp")
	var path_text = ""
	if move_comp and not (piece is City):
		if move_comp.path.size() > 0:
			path_text = " | Manual path (%d steps)" % move_comp.path.size()
		elif move_comp.goal != null:
			path_text = " | Moving to %s" % str(move_comp.goal)

	if piece.is_combatant() and piece.attack_comp:
		var target = piece.attack_comp.target
		if target and is_instance_valid(target):
			lbl_mode.text = "Target: %s  (F to clear)" % target.name
		else:
			lbl_mode.text = "Click an enemy in range to target"
		lbl_mode.text += path_text
	else:
		lbl_mode.text = path_text.trim_prefix(" | ")

	panel.show()

func refresh_stats():
	if current_viewed_piece and is_instance_valid(current_viewed_piece):
		show_stats(current_viewed_piece)
	else:
		hide_panels()   # the piece died or starved during the turn

func hide_panels():
	current_viewed_piece = null
	panel.hide()

func on_day_finished():
	## Called by TurnManager at the end of every day so open panels stay honest.
	if panel.visible:
		refresh_stats()
	_refresh_debug()

# ── Game over ─────────────────────────────────────────────────────────────────

func show_game_over(player_lost: bool, day: int):
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS   # usable while the tree is paused
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "Defeat" if player_lost else "Victory!"
	lbl.add_theme_font_size_override("font_size", 80)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	var sub = Label.new()
	var held := 0
	for c in s.board.cities:
		if is_instance_valid(c) and c.team == 1: held += 1
	sub.text = "The campaign lasted %d weeks. Cities held: %d." % [day, held]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Play Again"
	btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
	)
	vbox.add_child(btn)

	add_child(dim)

func _on_card_ui_choice_made(card_data: Dictionary, choice: String):
	set_decision_pending(false)
	card_choice_made.emit(card_data, choice)

# ── Debug overlay (F3) ────────────────────────────────────────────────────────

func _build_debug_overlay():
	debug_lbl = Label.new()
	debug_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	debug_lbl.offset_left = -300
	debug_lbl.offset_top = -420
	debug_lbl.offset_right = -10
	debug_lbl.offset_bottom = -10
	debug_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	debug_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	debug_lbl.add_theme_font_size_override("font_size", 13)
	debug_lbl.visible = false
	add_child(debug_lbl)

func toggle_debug():
	debug_lbl.visible = not debug_lbl.visible
	_refresh_debug()

func _refresh_debug():
	if debug_lbl == null or not debug_lbl.visible:
		return
	var lines: Array = ["WEATHER: %s" % s.weather.weather_name, "── active modifiers ──"]
	var desc: Array = s.modifiers.describe()
	if desc.is_empty():
		lines.append("(none)")
	else:
		lines.append_array(desc)
	lines.append("── deck: %d cards ──" % s.card_manager.deck.size())
	debug_lbl.text = "\n".join(lines)

# ── Mouse shield ──────────────────────────────────────────────────────────────

func is_mouse_over_ui() -> bool:
	## True when the cursor is over any visible control, including ones built at
	## runtime (city picker, game over). Keeps board clicks from firing through UI.
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE
