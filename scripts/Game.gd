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

const COST = {
	"infantry":  800,
	"artillery": 1000,
	"logistics": 800,
	"rail":      100,
	"train":     800,
}

@onready var ui = $UI
@onready var path_line = $PathLine

@onready var card_manager = $CardManager

@onready var rail_network = $RailNetwork

var game_state: Dictionary = { "move_cost": 1, "attack_modifier": 1.0 }
var pending_cards: Array    = []
var pending_restores: Array = []

var day: int = 0
var hex_to_move

var cities: Array = []
var units: Array  = []
var trains: Array = []

var rail_hexes: Dictionary          = {}
var rail_routes: Dictionary         = {}
var next_route_id: int              = 0
var building_route: Array           = []
var rail_nodes_building: Dictionary = {}

var city_menu: Panel = null
var city_menu_city: Node2D = null
var city_title_lbl: Label
var city_stock_lbl: Label
var city_buy_btns: Dictionary = {}

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
	city.set_neutral()
	grid = city.set_hex(Vector2i(0, 0), grid); cities.append(city)

	var city2 = CITY.instantiate(); add_child(city2, true)
	city2.set_enemy(); city2.is_hq = true
	grid = city2.set_hex(Vector2i(0, -3), grid); cities.append(city2)

	var city3 = CITY.instantiate(); add_child(city3, true)
	city3.is_hq = true
	grid = city3.set_hex(Vector2i(0, 3), grid); cities.append(city3)

	var logi = LOGI.instantiate(); add_child(logi, true)
	grid = logi.move_to(Vector2i(-1, -1), null, grid); units.append(logi)

	_unfreeze_all()

func _ready():
	card_manager.setup(self)
	rail_network.setup(self)
	
	ui.setup(COST)
	ui.next_day_requested.connect(self.clock_increment)
	ui.buy_requested.connect(self._on_city_buy_requested)
	ui.card_choice_made.connect(card_manager.resolve_choice)
	test_setup()
	_update_fow()

# ── Fog of War ────────────────────────────────────────────────────────────────

func _update_fow():
	var visible_hexes = {}

	for city in cities:
		if city.team == 1:
			for h in HEX.axial_radius(city.get_hex(), 2):
				visible_hexes[h] = true

	for unit in units:
		if unit.team == 1:
			var vision = max(2, unit.get_attack_range())
			for h in HEX.axial_radius(unit.get_hex(), vision):
				visible_hexes[h] = true

	for hex in grid.Grid:
		var piece = get_piece(hex)
		if piece:
			piece.visible = piece.team == 1 or visible_hexes.has(hex)

	for train in trains:
		if train.team != 1:
			train.visible = visible_hexes.has(train.get_hex())

	for hex in rail_hexes:
		if rail_hexes[hex].has("node"):
			rail_hexes[hex]["node"].visible = visible_hexes.has(hex)

func _on_city_buy_requested(item_type: String, city: Node2D):
	if city.team != 1: return
	var cost = COST[item_type]
	if city.get_resources() < cost: return

	var purchased = false
	match item_type:
		"infantry":  purchased = _spawn_unit_near_city(INFANTRY,  city)
		"artillery": purchased = _spawn_unit_near_city(ARTILLERY, city)
		"logistics": purchased = _spawn_unit_near_city(LOGI,      city)
		"rail":      rail_network.player_rail_stock  += 1; purchased = true
		"train":     rail_network.player_train_stock += 1; purchased = true

	if purchased:
		city.deplete(cost)
		ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock)

func _spawn_unit_near_city(scene: PackedScene, city: Node2D) -> bool:
	for adj in HEX.axial_neighbours(city.get_hex()):
		if not grid.Grid.has(adj): continue
		if get_piece(adj) == null and not rail_hexes.has(adj):
			var unit = scene.instantiate()
			add_child(unit, true)
			if city.team == 2: unit.set_enemy()
			# Initial placement — unit is NOT frozen (no action cost)
			grid = unit.move_to(adj, null, grid)
			units.append(unit)
			_update_fow()
			return true
	print("No free hex adjacent to %s" % city.name)
	return false

# ── Selection ─────────────────────────────────────────────────────────────────

func _select_piece(piece: Node2D, hex: Vector2i):
	if piece is City:
		if piece.team == 1:
			ui.open_city_menu(piece, rail_network.player_rail_stock, rail_network.player_train_stock)
		else:
			ui.show_stats(piece)
	else:
		ui.close_city_menu()
		ui.show_stats(piece)
		hex_to_move = hex

func _deselect_piece():
	path_line.clear_points()
	hex_to_move = null
	grid.deselect()
	ui.hide_panels()

func _hex_to_pos(hex): return grid.map_to_local(HEX.axial_to_oddr(hex))

# ── Combat ────────────────────────────────────────────────────────────────────

func _resolve_all_combat():
	var attacks: Array = []
	var to_die: Array = []
	
	# 1. Ask every combatant who they want to attack
	for unit in units:
		if not unit.combatant(): continue
		var t = unit.get_attack_target(grid)
		if t:
			attacks.append({ "attacker": unit, "target": t })

	# 2. Execute the attacks
	for pair in attacks:
		var attacker = pair["attacker"]
		var target   = pair["target"]
		
		# Skip if someone else already blew them up this loop
		if not is_instance_valid(attacker) or not is_instance_valid(target): continue
		
		# attacker.attack() returns true if the target's HP hit 0
		if attacker.attack(target):
			if target is City:
				target.capture(attacker.team, self)
			elif target not in to_die:
				to_die.append(target)
				
		# Did the attacker starve/die from attack costs?
		if attacker.get_resources() <= 0 and attacker not in to_die:
			to_die.append(attacker)

	# 3. Clean up the dead (Keep _die() in Game.gd so it can clear the arrays and grid)
	for dead in to_die:
		for unit in units:
			if is_instance_valid(unit) and unit.target == dead:
				unit.target = null
		_die(dead)

# ── Movement ──────────────────────────────────────────────────────────────────

func _resolve_all_movement() -> Array:
	var starved: Array = []
	for unit in units:
		if unit is City: continue

		# Delegate to the unit
		if unit.has_method("process_movement"):
			unit.process_movement(self)

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
	var selected = get_piece(hex)
	var previous_selected = get_piece(p_hex_to_move)

	if not previous_selected: return

	if not selected:
		if previous_selected.use_manual_path:
			# Calculate route from the LAST waypoint to the clicked hex
			var start_hex = previous_selected.get_hex()
			if previous_selected.path.size() > 0:
				start_hex = previous_selected.path.back()
				
			grid.enable_hex(start_hex)
			var route = grid.get_map_path(start_hex, hex)
			grid.disable_hex(start_hex)
			
			if route.size() > 1:
				for i in range(1, route.size()):
					previous_selected.add_waypoint(route[i])
		else:
			# Move to empty hex — set as goal, enable source hex immediately
			previous_selected.set_goal(hex)
		grid.enable_hex(p_hex_to_move)  # Available for other units' pathfinding now
		return

	var same_team = previous_selected.team == selected.team
	var dist      = HEX.axial_distance(p_hex_to_move, hex)

	if not same_team:
		if previous_selected.combatant() and dist <= previous_selected.get_attack_range():
			previous_selected.set_target(selected)
			ui.show_stats(previous_selected)
			return
	else:
		if dist == 1:
			_supply(previous_selected, selected)

# ── Death ─────────────────────────────────────────────────────────────────────

func _die(dead_piece):
	var dead_hex = dead_piece.get_hex()
	if dead_hex and grid.Grid.has(dead_hex):
		grid.Grid[dead_hex]["Piece"] = null

	if dead_piece in cities:
		cities.erase(dead_piece)
		if dead_piece.is_hq: _game_over(dead_piece.team == 1)
	else:
		units.erase(dead_piece)
		trains.erase(dead_piece)

	grid.enable_hex(dead_hex)
	dead_piece.queue_free()

func _game_over(player_lost: bool):
	ui.show_game_over(player_lost)
	get_tree().paused = true

func get_piece(hex):            return grid.get_piece(hex)
func set_piece(hex, piece=null): grid.set_piece(hex, piece)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event):
	if (event is InputEventMouse or event is InputEventMouseButton) and ui.is_mouse_over_ui():
		return
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
					# ROUTE THROUGH OUR UPDATED LOGIC INSTEAD OF HARDCODING set_goal
					_play_selected(hex, hex_to_move) 
					
					# If building a manual path, refresh the UI but KEEP the unit selected!
					if piece_to_move.use_manual_path:
						ui.show_stats(piece_to_move)
					else:
						# If auto-pathing, standard behavior is to finish and deselect
						_deselect_piece()

	elif event.is_action_pressed("deselect"):
		_deselect_piece()

	elif event is InputEventMouseMotion:
		if hex_to_move:
			var oddr_hex   = grid.local_to_map(get_global_mouse_position())
			var target_hex = HEX.oddr_to_axial(oddr_hex)
			if target_hex in grid.Grid.keys():
				var piece = get_piece(hex_to_move)
				if piece:
					if piece.use_manual_path:
						path_line.default_color = Color(1.0, 0.8, 0.2)
						# Draw fixed waypoints PLUS line to the mouse
						var points = PackedVector2Array()
						var prev = piece.get_hex()
						points.append(grid.map_to_local(HEX.axial_to_oddr(prev)))
						for p in piece.path:
							points.append(grid.map_to_local(HEX.axial_to_oddr(p)))
							prev = p
						
						grid.enable_hex(prev)
						var mouse_points = grid.get_hex_path(prev, target_hex)
						grid.disable_hex(prev)
						
						# Skip the first point so it doesn't overlap
						for i in range(1, mouse_points.size()):
							points.append(mouse_points[i])
						path_line.points = points
					else:
						path_line.default_color = Color(0.5, 1, 0.2)
						# Standard Auto-Pathing drawing
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
			KEY_M:
				if hex_to_move:
					var piece = get_piece(hex_to_move)
					if piece and piece.has_method("toggle_path_mode"):
						piece.toggle_path_mode()
						ui.show_stats(piece) # Refresh UI instantly
			KEY_F:
				if hex_to_move:
					var piece = get_piece(hex_to_move)
					if piece and piece.combatant():
						piece.clear_target()
						ui.show_stats(piece)
			KEY_R:
				if hex in grid.Grid.keys(): 
					rail_network.toggle_rail(hex)
			KEY_T: 
				rail_network.commit_rail_route()
			KEY_ESCAPE:
				if not rail_network.building_route.is_empty(): 
					rail_network.cancel_rail_build()
				else: 
					_deselect_piece()

# ── Enemy AI ──────────────────────────────────────────────────────────────────

func _run_enemy_ai():
	# Buy units if affordable
	for city in cities:
		if city.team != 2: continue
		var res = city.get_resources()
		if res >= COST["infantry"]:
			var choices = []
			if res >= COST["artillery"]: choices.append("artillery")
			if res >= COST["logistics"]: choices.append("logistics")
			choices.append("infantry")
			var choice = choices[randi() % choices.size()]
			var scene = {"infantry": INFANTRY, "artillery": ARTILLERY, "logistics": LOGI}[choice]
			if _spawn_unit_near_city(scene, city):
				city.deplete(COST[choice])

	# Move units toward targets
	for unit in units:
		if unit.team != 2 or unit is City or unit is Train: continue

		if unit.goal != null: continue  # Already has a goal, don't override

		if unit.get_resources() < 400:
			# Low on resources — head to nearest friendly city
			var best_city = null
			var best_dist = 9999
			for city in cities:
				if city.team == 2:
					var d = HEX.axial_distance(unit.get_hex(), city.get_hex())
					if d < best_dist:
						best_dist = d; best_city = city
			if best_city:
				unit.set_goal(best_city.get_hex())
				grid.enable_hex(unit.get_hex())
		else:
			# Move toward nearest player unit or city
			var best_target = null
			var best_dist   = 9999
			for p_unit in units:
				if p_unit.team == 1:
					var d = HEX.axial_distance(unit.get_hex(), p_unit.get_hex())
					if d < best_dist:
						best_dist = d; best_target = p_unit
			for city in cities:
				if city.team == 1:
					var d = HEX.axial_distance(unit.get_hex(), city.get_hex())
					if d < best_dist:
						best_dist = d; best_target = city
			if best_target:
				unit.set_goal(best_target.get_hex())
				grid.enable_hex(unit.get_hex())

# ── Day cycle ─────────────────────────────────────────────────────────────────

func _unfreeze_all():
	for unit in units:
		if is_instance_valid(unit):
			unit.unfreeze()

func clock_increment():
	day += 1
	ui.update_day(day)

	_unfreeze_all()
	card_manager.check_pending(day) # Delegate pending checks
	_run_enemy_ai()

	var starved = _resolve_all_movement()
	_resolve_all_combat()

	for unit in units:
		if unit.resupply_comp:
			unit.resupply_comp.process_resupply(grid)

	# Delegate card drawing
	var card_to_play = card_manager.draw_daily_card(day)
	if card_to_play: 
		ui.card_ui.display_card(card_to_play)
	else: 
		ui.card_ui.hide()

	for city in cities:
		var sieged = false
		for adj in HEX.axial_neighbours(city.get_hex()):
			if not grid.Grid.has(adj): continue
			var p = get_piece(adj)
			if p and p.team != city.team and p.combatant():
				sieged = true; break
		city.resource_comp.set_resupply_rate(0 if sieged else 100)
		city.next_day()

	for dead in starved:
		print("%s starved." % dead.name); _die(dead)

	_unfreeze_all()
	_update_fow()

	if ui.city_menu.visible: 
		ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock)
		
	if ui.panel.visible:
		ui.refresh_stats()

func _next_day_button():
	clock_increment()
