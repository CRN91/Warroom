extends CanvasLayer
class_name UIManager

# ── Signals ───────────────────────────────────────────────────────────────────
# These let the UI talk back to Game.gd without needing a hard reference to it
signal next_day_requested
signal buy_requested(item_type: String, city: Node2D)
signal card_choice_made(card_data: Dictionary, choice: String)

# ── UI References ─────────────────────────────────────────────────────────────
@onready var daycounter    = $DayCount
@onready var nextdaybutton = $NextDay
@onready var panel         = $Panel
@onready var lbl_name      = $Panel/VBoxContainer/Name
@onready var lbl_res       = $Panel/VBoxContainer/Resources
@onready var lbl_act       = $Panel/VBoxContainer/Action
@onready var lbl_mode      = $Panel/VBoxContainer/Mode
@onready var card_ui       = $CardUI

var current_viewed_piece: Node2D = null
var city_menu: Panel = null
var city_menu_city: Node2D = null
var city_title_lbl: Label
var city_stock_lbl: Label
var city_buy_btns: Dictionary = {}
var costs: Dictionary = {}

func setup(game_costs: Dictionary):
	costs = game_costs
	_build_city_menu()
	panel.hide()
	card_ui.hide()
	nextdaybutton.pressed.connect(func(): next_day_requested.emit())

func update_day(day: int):
	daycounter.text = "DAY " + str(day)

# ── City Menu ─────────────────────────────────────────────────────────────────

func _build_city_menu():
	city_menu = Panel.new()
	city_menu.custom_minimum_size = Vector2(200, 0)
	city_menu.position = Vector2(10, 160)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	city_menu.add_child(vbox)

	city_title_lbl = Label.new()
	vbox.add_child(city_title_lbl)
	vbox.add_child(HSeparator.new())

	for item in [
		["infantry",  "Infantry",     costs["infantry"]],
		["artillery", "Artillery",    costs["artillery"]],
		["logistics", "Logistics",    costs["logistics"]],
		["rail",      "Rail Segment", costs["rail"]],
		["train",     "Train",        costs["train"]],
	]:
		var btn = Button.new()
		btn.text = "%s  (%d)" % [item[1], item[2]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vbox.add_child(btn)
		city_buy_btns[item[0]] = btn
		# Bind the item type, so the signal knows what we clicked
		btn.pressed.connect(_on_buy_pressed.bind(item[0]))

	vbox.add_child(HSeparator.new())
	city_stock_lbl = Label.new()
	vbox.add_child(city_stock_lbl)

	add_child(city_menu)
	city_menu.hide()

func open_city_menu(city: Node2D, rail_stock: int, train_stock: int):
	city_menu_city = city
	refresh_city_menu(rail_stock, train_stock)
	city_menu.show()

func close_city_menu():
	city_menu.hide()
	city_menu_city = null

func refresh_city_menu(rail_stock: int, train_stock: int):
	if not city_menu_city: return
	city_title_lbl.text = "%s\n%d / %d resources" % [
		city_menu_city.name,
		city_menu_city.get_resources(),
		city_menu_city.get_max_resources()
	]
	var res = city_menu_city.get_resources()
	for key in city_buy_btns:
		city_buy_btns[key].disabled = res < costs[key]
	city_stock_lbl.text = "Stock: %d rail   %d trains" % [rail_stock, train_stock]

func _on_buy_pressed(item_type: String):
	if city_menu_city:
		# Tell Game.gd we want to buy something!
		buy_requested.emit(item_type, city_menu_city)

# ── Stats Panel ───────────────────────────────────────────────────────────────

func show_stats(piece):
	lbl_name.text = str(piece.name)
	lbl_res.text  = "Resources: %d / %d" % [piece.get_resources(), piece.get_max_resources()]
	lbl_act.text  = "Action: %s" % ("Used" if piece.is_frozen() else "Ready")

	var path_text = ""
	if piece.get("use_manual_path"):
		path_text = " | MANUAL PATH (%d waypoints)" % piece.movement_comp.path.size()
	elif piece.get("goal"):
		path_text = " | Goal: %s" % str(piece.goal)

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
		# If the unit died or starved during the turn, close the panel
		hide_panels()

func hide_panels():
	panel.hide()
	close_city_menu()

# ── Game Over Panel ───────────────────────────────────────────────────────────

func show_game_over(player_lost: bool):
	var p = Panel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lbl = Label.new()
	lbl.text = "You Lose" if player_lost else "You Win!"
	lbl.add_theme_font_size_override("font_size", 80)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(lbl)
	add_child(p)
	
func _on_card_ui_choice_made(card_data: Dictionary, choice: String):
	# When the CardUI registers a click, we bubble the signal up to Game.gd
	card_choice_made.emit(card_data, choice)
	
# ── Mouse Shield ──────────────────────────────────────────────────────────────

func is_mouse_over_ui() -> bool:
	# Get the mouse position relative to the UI layer
	var pos = get_viewport().get_mouse_position()
	
	# If the mouse is inside any of these rectangles, block the game board
	if nextdaybutton.visible and nextdaybutton.get_global_rect().has_point(pos): return true
	if panel.visible and panel.get_global_rect().has_point(pos): return true
	if card_ui.visible and card_ui.get_global_rect().has_point(pos): return true
	if city_menu and city_menu.visible and city_menu.get_global_rect().has_point(pos): return true
	
	return false
