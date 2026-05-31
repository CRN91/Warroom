extends Node2D

# Hexagonal tiled board
const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
@onready var grid = %Grid

# Board pieces
const INFANTRY = preload("res://scenes/infantry.tscn")
const ARTILLERY = preload("res://scenes/artillery.tscn")
const CITY     = preload("res://scenes/city.tscn")
const LOGI     = preload("res://scenes/logistics.tscn")
const TRAIN    = preload("res://scenes/train.tscn")
const RAIL     = preload("res://scenes/rail.tscn")

# UI
@onready var daycounter    = $CanvasLayer/DayCount
@onready var nextdaybutton = $CanvasLayer/NextDay
@onready var panel         = $CanvasLayer/Panel
@onready var lbl_name      = $CanvasLayer/Panel/VBoxContainer/Name
@onready var lbl_res       = $CanvasLayer/Panel/VBoxContainer/Resources
@onready var lbl_act       = $CanvasLayer/Panel/VBoxContainer/Action
@onready var card_ui       = $CanvasLayer/CardUI
@onready var path_line     = $PathLine

# Card logic
@onready var deck         = $Deck
@onready var card_library = $CardLibrary
@onready var resolver     = $CardResolver
var game_state: Dictionary = {
	"move_cost": 1,
	"attack_modifier": 1.0
}
var pending_cards: Array   = []
var pending_restores: Array = []

# Game logic
var day: int = 0
var hex_to_move

var cities: Array = []
var units: Array  = []
var trains: Array = []

# Rail state
# hex → { "route_id": int, "broken": bool, "node": Rail }
var rail_hexes: Dictionary  = {}
# route_id → Array[Vector2i]
var rail_routes: Dictionary = {}
var next_route_id: int = 0

# Rail currently being drawn (not yet committed)
var building_route: Array       = []
var rail_nodes_building: Dictionary = {}

# ── Cards ─────────────────────────────────────────────────────────────────────

func _on_card_choice(card_data: Dictionary, choice: String):
	resolver.resolve(card_data[choice]["effects"], self)

func _check_pending():
	for i in range(pending_cards.size() - 1, -1, -1):
		if pending_cards[i]["on_day"] <= day:
			deck.inject(card_library.get_card(pending_cards[i]["id"]), "soon")
			pending_cards.remove_at(i)
	for i in range(pending_restores.size() - 1, -1, -1):
		if pending_restores[i]["on_day"] <= day:
			game_state[pending_restores[i]["key"]] = pending_restores[i]["value"]
			pending_restores.remove_at(i)

# ── Test setup ────────────────────────────────────────────────────────────────

func test_setup():
	var piece = INFANTRY.instantiate()
	add_child(piece, true)
	grid = piece.move_to(Vector2i(2, 1), null, grid)
	units.append(piece)

	var piece2 = INFANTRY.instantiate()
	add_child(piece2, true)
	piece2.set_enemy()
	grid = piece2.move_to(Vector2i(1, -3), null, grid)
	units.append(piece2)
	
	var arty = ARTILLERY.instantiate()
	add_child(arty, true)
	arty.set_enemy()
	grid = arty.move_to(Vector2i(2, -3), null, grid)
	units.append(arty)

	var piece3 = INFANTRY.instantiate()
	add_child(piece3, true)
	grid = piece3.move_to(Vector2i(-1, 2), null, grid)
	units.append(piece3)

	var city = CITY.instantiate()
	add_child(city, true)
	grid = city.set_hex(Vector2i(0, 0), grid)
	cities.append(city)

	var city2 = CITY.instantiate()
	add_child(city2, true)
	city2.set_enemy()
	grid = city2.set_hex(Vector2i(0, -3), grid)
	cities.append(city2)

	var city3 = CITY.instantiate()
	add_child(city3, true)
	grid = city3.set_hex(Vector2i(0, 3), grid)
	cities.append(city3)

	var logi = LOGI.instantiate()
	add_child(logi, true)
	grid = logi.move_to(Vector2i(-1, -1), null, grid)
	units.append(logi)

	_unfreeze_all()

func _ready():
	card_library.load_library()
	for card in card_library.build_starting_deck(["western_front_intel", "weather_events", "command_decisions"]):
		deck.push(card)
	panel.hide()
	card_ui.hide()
	deck.load()
	test_setup()
	nextdaybutton.pressed.connect(self._next_day_button)

# ── Selection ─────────────────────────────────────────────────────────────────

func _select_piece(piece: Node2D, hex: Vector2i):
	show_stats(piece)
	hex_to_move = hex

func _deselect_piece():
	path_line.clear_points()
	hex_to_move = null
	grid.deselect()
	panel.hide()

# ── Combat / supply ───────────────────────────────────────────────────────────

func _die(dead_piece):
	var dead_hex = dead_piece.get_hex()
	if dead_hex and grid.Grid.has(dead_hex):
		grid.Grid[dead_hex]["Piece"] = null
	units.erase(dead_piece)
	trains.erase(dead_piece)
	dead_piece.queue_free()
	grid.enable_hex(dead_hex)

func _fight(piece1, piece2):
	var to_die = []
	var dist = HEX.axial_distance(piece1.get_hex(), piece2.get_hex())

	# piece1 attacks piece2 if in range
	if piece1.combatant() and dist <= piece1.get_attack_range():
		if piece1.attack(piece2):
			to_die.append(piece2)

	# piece2 counter-attacks only if piece1 is within its own range
	if piece2.combatant() and dist <= piece2.get_attack_range():
		if piece2.attack(piece1):
			to_die.append(piece1)

	for i in to_die:
		_die(i)

func _supply(piece1, piece2):
	if piece1.supplier > piece2.supplier:
		piece2.resupply_from(piece1)
	elif piece2.supplier > piece1.supplier:
		piece1.resupply_from(piece2)

func _play_selected(hex, p_hex_to_move):
	var selected          = grid.Grid[hex]["Piece"]
	var previous_selected = grid.Grid[p_hex_to_move]["Piece"]

	if not previous_selected:
		return

	if not selected:
		# Clicked an empty hex — move there
		grid = previous_selected.move_to(hex, p_hex_to_move, grid)
		return

	var same_team = previous_selected.is_allied() == selected.is_allied()
	var dist      = HEX.axial_distance(p_hex_to_move, hex)

	if not same_team:
		# Attack — check attacker's range
		if dist <= previous_selected.get_attack_range():
			if previous_selected.combatant() or selected.combatant():
				_fight(previous_selected, selected)
	else:
		# Supply — must be adjacent
		if dist == 1:
			_supply(previous_selected, selected)

# ── Rail building ─────────────────────────────────────────────────────────────

func _toggle_rail(hex: Vector2i):
	if hex in building_route:
		building_route.erase(hex)
		if rail_nodes_building.has(hex):
			rail_nodes_building[hex].queue_free()
			rail_nodes_building.erase(hex)
		return

	if rail_hexes.has(hex):
		print("Hex %s already has committed rail" % str(hex))
		return

	var rail_node = RAIL.instantiate()
	add_child(rail_node)
	rail_node.hex_pos  = hex
	rail_node.position = grid.map_to_local(HEX.axial_to_oddr(hex))
	rail_node.modulate = Color(0.6, 0.6, 1.0)  # Blue = preview

	building_route.append(hex)
	rail_nodes_building[hex] = rail_node
	print("Rail preview: %d hexes so far" % building_route.size())

func _commit_rail_route():
	if building_route.size() < 2:
		print("Need at least 2 hexes to commit a route")
		return

	var id = next_route_id
	next_route_id += 1

	for hex in building_route:
		var rail_node = rail_nodes_building[hex]
		rail_node.modulate = Color(1.0, 1.0, 1.0)  # White = committed
		rail_hexes[hex] = { "route_id": id, "broken": false, "node": rail_node }

	rail_routes[id] = building_route.duplicate()

	var train = TRAIN.instantiate()
	add_child(train, true)
	train.setup_route(rail_routes[id], id, self)
	trains.append(train)

	print("Route %d committed (%d hexes). Train spawned." % [id, building_route.size()])
	building_route.clear()
	rail_nodes_building.clear()

func _cancel_rail_build():
	for hex in building_route:
		if rail_nodes_building.has(hex):
			rail_nodes_building[hex].queue_free()
	building_route.clear()
	rail_nodes_building.clear()
	print("Rail route cancelled")

func _tick_trains():
	for train in trains:
		train.train_tick(self)

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event):
	if event.is_action_pressed("select"):
		var oddr_hex = grid.local_to_map(get_global_mouse_position())
		var hex      = HEX.oddr_to_axial(oddr_hex)
		if hex in grid.Grid.keys():
			grid.select_cell(oddr_hex)
			var selected = grid.Grid[hex]["Piece"]
			if selected:
				if hex_to_move:
					_play_selected(hex, hex_to_move)
					_deselect_piece()
				else:
					_select_piece(selected, hex)
			elif hex_to_move:
				grid = grid.Grid[hex_to_move]["Piece"].move_to(hex, hex_to_move, grid)
				_deselect_piece()

	elif event.is_action_pressed("deselect"):
		_deselect_piece()

	elif event is InputEventMouseMotion:
		if hex_to_move:
			var oddr_hex   = grid.local_to_map(get_global_mouse_position())
			var target_hex = HEX.oddr_to_axial(oddr_hex)
			if target_hex in grid.Grid.keys():
				grid.enable_hex(hex_to_move)
				path_line.points = grid.get_hex_path(hex_to_move, target_hex)
				grid.disable_hex(hex_to_move)
			else:
				path_line.clear_points()

	elif event is InputEventKey and event.pressed and not event.echo:
		var oddr_hex = grid.local_to_map(get_global_mouse_position())
		var hex      = HEX.oddr_to_axial(oddr_hex)

		match event.keycode:
			KEY_R:
				if hex in grid.Grid.keys():
					_toggle_rail(hex)
			KEY_T:
				_commit_rail_route()
			KEY_ESCAPE:
				if not building_route.is_empty():
					_cancel_rail_build()

# ── Day cycle ─────────────────────────────────────────────────────────────────

func _unfreeze_all():
	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece:
			piece.unfreeze()

func clock_increment():
	day += 1
	daycounter.text = "DAY " + str(day)

	_unfreeze_all()
	_check_pending()

	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece:
			piece.unfreeze()
			for target_hex in grid.Grid:
				if target_hex <= hex:
					continue  # Each pair processed once
				var target_piece = grid.Grid[target_hex]["Piece"]
				if not target_piece:
					continue
					
				var dist = HEX.axial_distance(hex, target_hex)
				var same_team = piece.is_allied() == target_piece.is_allied()
				if not same_team and piece.combatant() and target_piece.combatant():
					# Fight if either can reach the other
					if dist <= piece.get_attack_range() or dist <= target_piece.get_attack_range():
						_fight(piece, target_piece)
				elif same_team and dist == 1:
					_supply(piece, target_piece)

	# Card draw
	var required_type = ["decision", "intel", "event"][day % 3]
	var card_to_play  = null
	for i in range(deck.size()):
		var checked = deck.queue[i]
		if deck.len() > 1 and checked["type"] == required_type:
			card_to_play = checked
			deck.queue.remove_at(i)
			break
	if card_to_play != null:
		card_ui.display_card(card_to_play)
	else:
		card_ui.hide()

	# City replenish
	for city in cities:
		city.restore(100)

	# Unit auto-path and daily depletion
	for unit in units:
		if unit.path and unit.path.size() > 0:
			var next_hex = unit.path[0]
			if grid.Grid[next_hex]["Piece"] == null:
				unit.move_to(next_hex, unit.get_hex(), grid)
				unit.path.remove_at(0)
		unit.auto_deplete()

	# Train movement and supply delivery
	_tick_trains()
	_unfreeze_all()

func show_stats(piece):
	lbl_name.text = str(piece.name)
	lbl_res.text  = "Resources: %d / %d" % [piece.get_resources(), piece.get_max_resources()]
	lbl_act.text  = "Frozen: %s" % str(piece.is_frozen())
	panel.show()

func _next_day_button():
	clock_increment()
