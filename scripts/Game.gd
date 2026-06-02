extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
@onready var grid = %Grid

const INFANTRY  = preload("res://scenes/infantry.tscn")
const ARTILLERY = preload("res://scenes/artillery.tscn")
const CITY      = preload("res://scenes/city.tscn")
const LOGI      = preload("res://scenes/logistics.tscn")
const TRAIN     = preload("res://scenes/train.tscn")
const RAIL      = preload("res://scenes/rail.tscn")

# Unit costs
const COST = {
	"infantry":  800,
	"artillery": 1000,
	"logistics": 800,
	"rail":      100,
	"train":     800,
}

@onready var daycounter    = $CanvasLayer/DayCount
@onready var nextdaybutton = $CanvasLayer/NextDay
@onready var panel         = $CanvasLayer/Panel
@onready var lbl_name      = $CanvasLayer/Panel/VBoxContainer/Name
@onready var lbl_res       = $CanvasLayer/Panel/VBoxContainer/Resources
@onready var lbl_act       = $CanvasLayer/Panel/VBoxContainer/Action
@onready var lbl_mode      = $CanvasLayer/Panel/VBoxContainer/Mode
@onready var card_ui       = $CanvasLayer/CardUI
@onready var path_line     = $PathLine

@onready var deck         = $Deck
@onready var card_library = $CardLibrary
@onready var resolver     = $CardResolver

var game_state: Dictionary = { "move_cost": 1, "attack_modifier": 1.0 }
var pending_cards: Array    = []
var pending_restores: Array = []

var day: int = 0
var hex_to_move

var cities: Array = []
var units: Array  = []
var trains: Array = []

# ── Player inventory (bought from cities, consumed when building) ─────────────
var player_rail_stock: int  = 0
var player_train_stock: int = 0

var rail_hexes: Dictionary       = {}
var rail_routes: Dictionary      = {}
var next_route_id: int           = 0
var building_route: Array        = []
var rail_nodes_building: Dictionary = {}

# ── City menu (built in code) ─────────────────────────────────────────────────
var city_menu: Panel = null
var city_menu_city: Node2D = null
var city_title_lbl: Label
var city_stock_lbl: Label
var city_buy_btns: Dictionary = {}  # "infantry" → Button, etc.

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

# ── Setup ─────────────────────────────────────────────────────────────────────

func test_setup():
	var p1 = INFANTRY.instantiate(); add_child(p1, true)
	grid = p1.move_to(Vector2i(2, 1), null, grid); units.append(p1)

	var p2 = INFANTRY.instantiate(); add_child(p2, true)
	p2.set_enemy()
	grid = p2.move_to(Vector2i(1, -3), null, grid); units.append(p2)

	var arty = ARTILLERY.instantiate(); add_child(arty, true)
	arty.set_enemy()
	grid = arty.move_to(Vector2i(2, -3), null, grid); units.append(arty)

	var p3 = INFANTRY.instantiate(); add_child(p3, true)
	grid = p3.move_to(Vector2i(-1, 2), null, grid); units.append(p3)

	var city = CITY.instantiate(); add_child(city, true)
	grid = city.set_hex(Vector2i(0, 0), grid); cities.append(city)

	var city2 = CITY.instantiate(); add_child(city2, true)
	city2.set_enemy()
	grid = city2.set_hex(Vector2i(0, -3), grid); cities.append(city2)

	var city3 = CITY.instantiate(); add_child(city3, true)
	grid = city3.set_hex(Vector2i(0, 3), grid); cities.append(city3)

	var logi = LOGI.instantiate(); add_child(logi, true)
	grid = logi.move_to(Vector2i(-1, -1), null, grid); units.append(logi)

	_unfreeze_all()

func _ready():
	card_library.load_library()
	for card in card_library.build_starting_deck(["western_front_intel", "weather_events", "command_decisions"]):
		deck.push(card)
	panel.hide()
	card_ui.hide()
	deck.load()
	_build_city_menu()
	test_setup()
	nextdaybutton.pressed.connect(self._next_day_button)

# ── City menu ─────────────────────────────────────────────────────────────────

func _build_city_menu():
	city_menu = Panel.new()
	city_menu.custom_minimum_size = Vector2(200, 0)
	city_menu.position = Vector2(10, 160)  # Below the stats panel

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	city_menu.add_child(vbox)

	city_title_lbl = Label.new()
	city_title_lbl.text = "City"
	vbox.add_child(city_title_lbl)

	var sep = HSeparator.new(); vbox.add_child(sep)

	# Purchase buttons — order: units first, then infrastructure
	var items = [
		["infantry",  "Infantry",       COST["infantry"]],
		["artillery", "Artillery",      COST["artillery"]],
		["logistics", "Logistics",      COST["logistics"]],
		["rail",      "Rail Segment",   COST["rail"]],
		["train",     "Train",          COST["train"]],
	]
	for item in items:
		var btn = Button.new()
		btn.text = "%s  (%d)" % [item[1], item[2]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vbox.add_child(btn)
		city_buy_btns[item[0]] = btn
		btn.pressed.connect(_on_buy_pressed.bind(item[0]))

	var sep2 = HSeparator.new(); vbox.add_child(sep2)

	city_stock_lbl = Label.new()
	city_stock_lbl.text = "Stock: 0 rail  0 trains"
	vbox.add_child(city_stock_lbl)

	$CanvasLayer.add_child(city_menu)
	city_menu.hide()

func _open_city_menu(city: Node2D):
	city_menu_city = city
	_refresh_city_menu()
	city_menu.show()

func _close_city_menu():
	city_menu.hide()
	city_menu_city = null

func _refresh_city_menu():
	if not city_menu_city:
		return

	var res     = city_menu_city.get_resources()
	var max_res = city_menu_city.get_max_resources()
	city_title_lbl.text = "%s\n%d / %d resources" % [city_menu_city.name, res, max_res]

	# Grey out buttons the city can't afford
	for key in city_buy_btns:
		city_buy_btns[key].disabled = res < COST[key]

	city_stock_lbl.text = "Stock: %d rail   %d trains" % [player_rail_stock, player_train_stock]

## Handles all purchase button presses.
func _on_buy_pressed(item_type: String):
	if not city_menu_city:
		return
	if not city_menu_city.is_allied():
		return
	var cost = COST[item_type]
	if city_menu_city.get_resources() < cost:
		return

	var purchased = false

	match item_type:
		"infantry":
			purchased = _spawn_unit_near_city(INFANTRY, city_menu_city)
		"artillery":
			purchased = _spawn_unit_near_city(ARTILLERY, city_menu_city)
		"logistics":
			purchased = _spawn_unit_near_city(LOGI, city_menu_city)
		"rail":
			player_rail_stock += 1
		"train":
			player_train_stock += 1

	if purchased:
		city_menu_city.deplete(cost)

	_refresh_city_menu()

## Spawns a unit on the first free hex adjacent to the city.
func _spawn_unit_near_city(scene: PackedScene, city: Node2D):
	var city_hex = city.get_hex()
	for adj in HEX.axial_neighbours(city_hex):
		if not grid.Grid.has(adj):
			continue
		if get_piece(adj) == null and not rail_hexes.has(adj):
			var unit = scene.instantiate()
			add_child(unit, true)
			grid = unit.move_to(adj, null, grid)
			units.append(unit)
			print("Spawned %s at %s" % [unit.name, str(adj)])
			return true
	print("No free adjacent hex to spawn unit near %s" % city.name)
	return false

# ── Selection ─────────────────────────────────────────────────────────────────

func _select_piece(piece: Node2D, hex: Vector2i):
	if piece is City:
		if piece.is_allied():
			_open_city_menu(piece)
		else:
			show_stats(piece)  # Enemy city — stats only, no shop
	else:
		_close_city_menu()
		show_stats(piece)
		hex_to_move = hex

func _deselect_piece():
	path_line.clear_points()
	hex_to_move = null
	grid.deselect()
	panel.hide()
	_close_city_menu()

# ── Combat resolution ─────────────────────────────────────────────────────────

func _find_enemy_in_range(unit: Node2D) -> Node2D:
	var range_hexes = HEX.axial_radius(unit.get_hex(), unit.get_attack_range())
	var possible_targets = []

	for hex in range_hexes:
		if not grid.Grid.has(hex):
			continue
		var piece = get_piece(hex)
		if piece and piece.is_allied() != unit.is_allied():
			possible_targets.append(piece)

	if possible_targets.is_empty():
		return null

	for t in possible_targets:
		if t.combatant(): return t
	for t in possible_targets:
		if t is Logistics: return t
	return possible_targets[0]

func _get_attack_target(unit: Node2D) -> Node2D:
	if unit.pending_attack and not is_instance_valid(unit.pending_attack):
		unit.pending_attack = null
	if unit.target and not is_instance_valid(unit.target):
		unit.target = null

	if unit.pending_attack:
		var t = unit.pending_attack
		unit.pending_attack = null
		return t

	if unit.is_frozen():
		return null

	if unit.target and is_instance_valid(unit.target):
		var dist = HEX.axial_distance(unit.get_hex(), unit.target.get_hex())
		if dist <= unit.get_attack_range():
			return unit.target

	return _find_enemy_in_range(unit)

func _resolve_all_combat():
	var attack_pairs: Array = []
	for unit in units:
		if not unit.combatant(): continue
		var t = _get_attack_target(unit)
		if t and is_instance_valid(t):
			attack_pairs.append({ "attacker": unit, "target": t })

	var to_die: Array = []
	for pair in attack_pairs:
		var attacker = pair["attacker"]
		var target   = pair["target"]
		if not is_instance_valid(attacker) or not is_instance_valid(target): continue
		if attacker.attack(target) and target not in to_die:
			to_die.append(target)
		if attacker.get_resources() <= 0 and attacker not in to_die:
			to_die.append(attacker)

	for dead in to_die:
		for unit in units:
			if is_instance_valid(unit) and unit.target == dead:
				unit.target = null
		_die(dead)

func _resolve_all_movement():
	var starved: Array = []
	for unit in units:
		if unit.get_pending_move():
			unit.move_to(unit.pending_move, unit.get_hex(), grid)
			unit.clear_pending_move()
		elif unit.path and unit.path.size() > 0:
			var next_hex = unit.path[0]
			if get_piece(next_hex) == null:
				unit.move_to(next_hex, unit.get_hex(), grid)
				unit.path.remove_at(0)
		if unit.next_day():
			starved.append(unit)
	return starved

# ── Supply ────────────────────────────────────────────────────────────────────

func _supply(piece1, piece2):
	if piece1.supplier > piece2.supplier:
		piece2.resupply_from(piece1)
	elif piece2.supplier > piece1.supplier:
		piece1.resupply_from(piece2)

# ── Play selected ─────────────────────────────────────────────────────────────

func _play_selected(hex, p_hex_to_move):
	var selected          = get_piece(hex)
	var previous_selected = get_piece(p_hex_to_move)

	if not previous_selected: return

	if not selected:
		previous_selected.queue_move(hex)
		return

	var same_team = previous_selected.is_allied() == selected.is_allied()
	var dist      = HEX.axial_distance(p_hex_to_move, hex)

	if not same_team:
		if previous_selected.combatant() and dist <= previous_selected.get_attack_range():
			previous_selected.set_target(selected)
			show_stats(previous_selected)
			return
	else:
		if dist == 1:
			_supply(previous_selected, selected)

# ── Death ─────────────────────────────────────────────────────────────────────

func _die(dead_piece):
	var dead_hex = dead_piece.get_hex()
	if dead_hex and grid.Grid.has(dead_hex):
		grid.Grid[dead_hex]["Piece"] = null
	units.erase(dead_piece)
	trains.erase(dead_piece)
	grid.enable_hex(dead_hex)
	dead_piece.queue_free()

# ── Rail ──────────────────────────────────────────────────────────────────────

func _toggle_rail(hex):
	# Remove from building route
	if hex in building_route:
		var is_back  = hex == building_route.back()
		var is_front = hex == building_route.front()
		if is_back or is_front:
			if is_back: building_route.pop_back()
			else:       building_route.pop_front()
			if rail_nodes_building.has(hex):
				rail_nodes_building[hex].queue_free()
				rail_nodes_building.erase(hex)
			player_rail_stock += 1  # Refund the rail segment
		else:
			print("Can only remove from either end of the route")
		return

	if rail_hexes.has(hex): return

	var piece = grid.get_piece(hex)
	if piece is City: return

	# Must have at least 1 rail in stock to place
	if player_rail_stock < 1:
		print("Not enough rail stock (have %d, need 1)" % player_rail_stock)
		return

	# Must be adjacent to existing route end (or first hex)
	if building_route.size() > 0:
		var add_to_back   = hex in HEX.axial_neighbours(building_route.back())
		var add_to_front  = hex in HEX.axial_neighbours(building_route.front())
		if not add_to_back and not add_to_front:
			print("Hex must be adjacent to either end of the current route")
			return

	var rail_node = RAIL.instantiate()
	add_child(rail_node)
	rail_node.hex_pos  = hex
	rail_node.position = _hex_to_pos(hex)
	rail_node.modulate = Color(0.6, 0.6, 1.0)  # Blue = preview

	if building_route.size() > 0 and hex in HEX.axial_neighbours(building_route.front()):
		building_route.insert(0, hex)
	else:
		building_route.append(hex)

	rail_nodes_building[hex] = rail_node
	player_rail_stock -= 1  # Consume 1 rail segment
	print("Rail placed at %s | Stock: %d rail  %d trains" % [str(hex), player_rail_stock, player_train_stock])

func _hex_to_pos(hex):
	return grid.map_to_local(HEX.axial_to_oddr(hex))

func _commit_rail_route():
	if building_route.size() < 2:
		print("Need at least 2 hexes to commit a route")
		return

	# Must have at least 1 train in stock to run the route
	if player_train_stock < 1:
		print("Need at least 1 train in stock to commit a route (have %d)" % player_train_stock)
		return

	var id = next_route_id
	next_route_id += 1

	for hex in building_route:
		var rail_node = rail_nodes_building[hex]
		rail_node.modulate = Color(1.0, 1.0, 1.0)
		rail_hexes[hex] = { "route_id": id, "broken": false, "node": rail_node }

	rail_routes[id] = building_route.duplicate()

	var train = TRAIN.instantiate()
	add_child(train, true)
	train.setup_route(rail_routes[id], id, self)
	trains.append(train)
	units.append(train)

	player_train_stock -= 1  # Consume 1 train
	print("Route %d committed. Train deployed. Stock: %d rail  %d trains" % [id, player_rail_stock, player_train_stock])

	building_route.clear()
	rail_nodes_building.clear()

func _cancel_rail_build():
	# Refund all placed rail segments
	player_rail_stock += building_route.size()
	for hex in building_route:
		if rail_nodes_building.has(hex):
			rail_nodes_building[hex].queue_free()
	building_route.clear()
	rail_nodes_building.clear()
	print("Rail route cancelled. Stock: %d rail  %d trains" % [player_rail_stock, player_train_stock])

func _tick_trains():
	for train in trains:
		train.train_tick(self)

# ── Grid helpers ──────────────────────────────────────────────────────────────

func get_piece(hex):      return grid.get_piece(hex)
func set_piece(hex, piece=null): grid.set_piece(hex, piece)

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event):
	if event.is_action_pressed("select"):
		var oddr_hex = grid.local_to_map(get_global_mouse_position())
		var hex      = HEX.oddr_to_axial(oddr_hex)
		if hex in grid.Grid.keys():
			grid.select_hex(oddr_hex)
			var selected = get_piece(hex)
			if selected:
				if hex_to_move:
					_play_selected(hex, hex_to_move)
					_deselect_piece()
				else:
					_select_piece(selected, hex)
			elif hex_to_move:
				var piece_to_move = get_piece(hex_to_move)
				if piece_to_move:
					piece_to_move.queue_move(hex)
				_deselect_piece()

	elif event.is_action_pressed("deselect"):
		_deselect_piece()

	elif event is InputEventMouseMotion:
		if hex_to_move:
			var oddr_hex   = grid.local_to_map(get_global_mouse_position())
			var target_hex = HEX.oddr_to_axial(oddr_hex)
			if target_hex in grid.Grid.keys():
				if get_piece(hex_to_move):
					grid.enable_hex(hex_to_move)
					path_line.points = grid.get_hex_path(hex_to_move, target_hex)
					grid.disable_hex(hex_to_move)
				else:
					path_line.clear_points()
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
			KEY_F:
				if hex_to_move:
					var piece = get_piece(hex_to_move)
					if piece and piece.combatant():
						piece.clear_target()
						show_stats(piece)
			KEY_ESCAPE:
				if not building_route.is_empty():
					_cancel_rail_build()
				else:
					_deselect_piece()

# ── Day cycle ─────────────────────────────────────────────────────────────────

func _unfreeze_all():
	for unit in units:
		if is_instance_valid(unit):
			unit.unfreeze()

func clock_increment():
	day += 1
	daycounter.text = "DAY " + str(day)

	_unfreeze_all()
	_check_pending()
	

	var starved = _resolve_all_movement()
	_resolve_all_combat()

	for hex in grid.Grid:
		var piece = get_piece(hex)
		if not piece: continue
		for adjacent in HEX.axial_neighbours(hex):
			if not grid.Grid.has(adjacent): continue
			var adj_piece = get_piece(adjacent)
			if adj_piece and adj_piece.is_allied() == piece.is_allied() and hex < adjacent:
				_supply(piece, adj_piece)

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

	for city in cities:
		city.next_day()

	for dead in starved:
		print("%s starved." % dead.name)
		_die(dead)

	_tick_trains()
	_unfreeze_all()

	# Refresh city menu if open (resources may have changed)
	if city_menu.visible:
		_refresh_city_menu()

# ── Stats panel ───────────────────────────────────────────────────────────────

func show_stats(piece):
	lbl_name.text = str(piece.name)
	lbl_res.text  = "Resources: %d / %d" % [piece.get_resources(), piece.get_max_resources()]
	lbl_act.text  = "Action: %s" % ("Used" if piece.is_frozen() else "Ready")

	if piece.combatant():
		if piece.target and is_instance_valid(piece.target):
			lbl_mode.text = "Target: %s  (F to clear)" % piece.target.name
		else:
			lbl_mode.text = "Range: %d | Click enemy to target" % piece.get_attack_range()
	else:
		lbl_mode.text = ""

	panel.show()

func _next_day_button():
	clock_increment()
