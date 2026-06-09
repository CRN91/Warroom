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

# Built-in-code UI
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

# ── Top bar (date / season / weather) ─────────────────────────────────────────

func _build_top_bar():
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_top = 8
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", _hud_style())

	top_bar_lbl = Label.new()
	top_bar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(top_bar_lbl)
	add_child(bar)

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

	var overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_theme_stylebox_override("panel", _hud_style(0.96))

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
			overlay.queue_free()
		)
		vbox.add_child(btn)

	add_child(overlay)

# ── Stats panel ───────────────────────────────────────────────────────────────

func show_stats(piece):
	current_viewed_piece = piece
	lbl_name.text = str(piece.name)
	lbl_res.text  = "Resources: %d / %d" % [piece.get_resources(), piece.get_max_resources()]

	if piece is City:
		var role := "Capital" if piece.is_capital else "City"
		lbl_act.text = "%s — income %d/week" % [role, piece.resource_comp.replenish_rate]
	else:
		lbl_act.text = "Action: %s" % ("Used" if piece.is_frozen() else "Ready")

	var move_comp = piece.get("movement_comp")
	var path_text = ""
	if move_comp and not (piece is City):
		if move_comp.path.size() > 0:
			path_text = " | Manual path (%d steps)" % move_comp.path.size()
		elif move_comp.goal != null:
			path_text = " | Moving to %s" % str(move_comp.goal)

	if piece.is_combatant():
		var target = piece.attack_comp.target
		if target and is_instance_valid(target):
			lbl_mode.text = "Target: %s  (F to clear)" % target.name
		else:
			lbl_mode.text = "Range: %d | Click enemy to target" % piece.get_attack_range()
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

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dim.add_child(vbox)

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
