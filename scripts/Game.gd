extends Node2D
class_name Game

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@onready var grid = %Grid
@onready var ui = $UI
@onready var path_line = $PathLine
@onready var card_manager = $CardManager
@onready var enemy_ai = $EnemyAI
@onready var rail_network = $RailNetwork
@onready var fow_manager = $FowManager

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

var game_state: Dictionary = { "move_cost": 1, "attack_modifier": 1.0 }
var pending_cards: Array    = []
var pending_restores: Array = []
var _ghosted_hexes: Array   = []
var recent_death_hexes: Array = []

var day: int = 0
var hex_to_move: Vector2i

var cities: Array = []
var units: Array  = []
var trains: Array = []

# UI state variables
var city_menu: Panel = null
var city_menu_city: Node2D = null
var city_title_lbl: Label
var city_stock_lbl: Label
var city_buy_btns: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready():
	card_manager.setup(self)
	enemy_ai.setup(self)
	fow_manager.setup(grid, rail_network, cities, units)
	
	rail_network.setup(grid)
	rail_network.train_created.connect(_on_train_created)
	
	ui.setup(COST)
	ui.next_day_requested.connect(clock_increment)
	ui.buy_requested.connect(_on_city_buy_requested)
	ui.card_choice_made.connect(card_manager.resolve_choice)
	
	test_setup()
	fow_manager.update_fow()

func test_setup():
	var p1 = INFANTRY.instantiate(); add_child(p1, true)
	p1.setup(grid)
	p1.move_to(Vector2i(2, 1)); units.append(p1)

	var p2 = INFANTRY.instantiate(); add_child(p2, true)
	p2.setup(grid)
	p2.set_enemy()
	p2.move_to(Vector2i(1, -3)); units.append(p2)

	var arty = ARTILLERY.instantiate(); add_child(arty, true)
	arty.setup(grid)
	arty.set_enemy()
	arty.move_to(Vector2i(2, -3)); units.append(arty)

	var p3 = INFANTRY.instantiate(); add_child(p3, true)
	p3.setup(grid)
	p3.move_to(Vector2i(-1, 2)); units.append(p3)

	var city = CITY.instantiate(); add_child(city, true)
	city.setup(grid)
	city.set_neutral()
	city.set_hex(Vector2i(0, 0)); cities.append(city)

	var city2 = CITY.instantiate(); add_child(city2, true)
	city2.setup(grid)
	city2.set_enemy(); city2.is_hq = true
	city2.set_hex(Vector2i(0, -3)); cities.append(city2)

	var city3 = CITY.instantiate(); add_child(city3, true)
	city3.setup(grid)
	city3.is_hq = true
	city3.set_hex(Vector2i(0, 3)); cities.append(city3)

	var logi = LOGI.instantiate(); add_child(logi, true)
	logi.setup(grid)
	logi.move_to(Vector2i(-1, -1)); units.append(logi)

	_unfreeze_all()

# ── Spawning & Purchasing ─────────────────────────────────────────────────────

func _on_train_created(train: Node2D):
	trains.append(train)
	units.append(train)

func _on_city_buy_requested(item_type: String, city: Node2D):
	if city.team != 1: return
	var cost = COST[item_type]
	if city.get_resources() < cost: return

	var purchased = false
	if item_type == "rail":
		rail_network.player_rail_stock += 1
		purchased = true
	elif item_type == "train":
		rail_network.player_train_stock += 1
		purchased = true
	else:
		var scene = {"infantry": INFANTRY, "artillery": ARTILLERY, "logistics": LOGI}[item_type]
		purchased = _spawn_unit_near_city(scene, city)

	if purchased:
		city.deplete(cost)
		ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock)
		
func _spawn_unit_near_city(scene: PackedScene, city: Node2D) -> bool:
	for adj in HEX.axial_neighbours(city.get_hex()):
		if not grid.Grid.has(adj): continue
		
		if get_piece(adj) == null and not rail_network.rail_hexes.has(adj) and not adj in recent_death_hexes:
			var unit = scene.instantiate()
			unit.setup(grid)
			add_child(unit, true)
			
			if city.team == 2: 
				unit.set_enemy()
				
			unit.move_to(adj)
			units.append(unit)
			fow_manager.update_fow()
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
	hex_to_move = Vector2i()
	grid.deselect()
	ui.hide_panels()

# ── Combat ────────────────────────────────────────────────────────────────────

func _resolve_all_combat():
	var attacks: Array = []
	var to_die: Array = []
	
	for unit in units:
		if not unit.is_combatant(): continue
		var target = unit.get_attack_target()
		if target:
			attacks.append({ "attacker": unit, "target": target })

	for pair in attacks:
		var attacker = pair["attacker"]
		var target   = pair["target"]
		
		if not is_instance_valid(attacker) or not is_instance_valid(target): continue
		
		if attacker.attack(target):
			if target is City:
				target.capture(attacker.team, self)
			elif target not in to_die:
				to_die.append(target)

		# If the target hex has a rail on it, the attack damages the line
		var target_hex = target.get_hex()
		if target_hex and rail_network.rail_hexes.has(target_hex):
			rail_network.break_rail_at(target_hex)
			
		if attacker.get_resources() <= 0 and attacker not in to_die:
			to_die.append(attacker)

	for dead in to_die:
		for unit in units:
			if is_instance_valid(unit) and unit.attack_comp and unit.get_attack_target() == dead:
				unit.set_attack_target(null)
		_die(dead)

# ── Movement ──────────────────────────────────────────────────────────────────

func _resolve_all_movement() -> Array:
	var starved: Array = []
	for unit in units:
		if unit is City: continue

		if unit.has_method("process_movement"):
			unit.process_movement()

		if unit.next_day():
			starved.append(unit)

	return starved

func _handle_movement_command(unit, target_hex):
	if unit.use_manual_path:
		var start_hex = unit.movement_comp.path.back() if unit.movement_comp.path.size() > 0 else unit.get_hex()

		_ghost_grid() 
		var route = grid.get_map_path(start_hex, target_hex)
		_unghost_grid() 

		for i in range(1, route.size()):
			unit.add_waypoint(route[i])
	else:
		unit.set_destination(target_hex)
		
func _ghost_grid():
	_ghosted_hexes.clear()
	for h in grid.Grid:
		var p = get_piece(h)
		if p:
			if p is City: continue 
			grid.enable_hex(h)
			_ghosted_hexes.append(h)

func _unghost_grid():
	for h in _ghosted_hexes:
		grid.disable_hex(h)
	_ghosted_hexes.clear()

func _play_selected(hex, p_hex_to_move):
	var selected    = get_piece(hex)
	var active_unit = get_piece(p_hex_to_move)
	if not active_unit: return

	# ── Logistics repair action ───────────────────────────────────────────────
	# Logistics clicking an adjacent broken rail hex spends 50 resources to fix it.
	if active_unit is Logistics and not selected:
		if rail_network.rail_hexes.has(hex) and rail_network.rail_hexes[hex]["broken"]:
			var dist = HEX.axial_distance(p_hex_to_move, hex)
			if dist <= 1:
				rail_network.repair_rail_at(hex, active_unit)
				ui.refresh_stats()
				return

	if active_unit.use_manual_path:
		if not selected is City:
			_handle_movement_command(active_unit, hex)
		return

	var click_as_empty = (not selected) or (not selected.visible and selected.team != active_unit.team)

	if click_as_empty:
		_handle_movement_command(active_unit, hex)
		grid.enable_hex(p_hex_to_move) 
		return

	var dist = HEX.axial_distance(p_hex_to_move, hex)

	if active_unit.team != selected.team:
		if active_unit.is_combatant() and dist <= active_unit.get_attack_range():
			active_unit.set_attack_target(selected)
			ui.show_stats(active_unit)
	elif dist == 1:
		var active_is_supplier   = not active_unit.is_combatant()
		var selected_is_supplier = not selected.is_combatant()

		if active_is_supplier and not selected_is_supplier:
			selected.receive_from(active_unit)    
		elif selected_is_supplier and not active_is_supplier:
			active_unit.receive_from(selected)
		elif active_is_supplier and selected_is_supplier:
			active_unit.receive_from(selected)

# ── Death ─────────────────────────────────────────────────────────────────────

func _die(dead_piece):
	var dead_hex = dead_piece.get_hex()
	if dead_hex and grid.Grid.has(dead_hex):
		grid.Grid[dead_hex]["Piece"] = null
		
		if not dead_hex in recent_death_hexes:
			recent_death_hexes.append(dead_hex)

	if dead_piece in cities:
		cities.erase(dead_piece)
		if dead_piece.is_hq: 
			_game_over(dead_piece.team == 1)
	else:
		units.erase(dead_piece)
		trains.erase(dead_piece)

	grid.enable_hex(dead_hex)
	dead_piece.queue_free()   # train.gd's tree_exiting notifies rail_network automatically

func _game_over(player_lost: bool):
	ui.show_game_over(player_lost)
	get_tree().paused = true

func get_piece(hex): 
	return grid.get_piece(hex)
	
func set_piece(hex, piece=null): 
	grid.set_piece(hex, piece)

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
			
			# ── Deploy train onto empty route ─────────────────────────────────
			# If there is no piece on the hex but it has rail with no train,
			# and the player has train stock, deploy one there.
			if not selected and not hex_to_move:
				if rail_network.can_deploy_train(hex) and rail_network.player_train_stock > 0:
					if rail_network.deploy_train_from_stock(hex):
						ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock)
					return
			
			if selected:
				if hex_to_move:
					_play_selected(hex, hex_to_move)
					_deselect_piece()
				else:
					_select_piece(selected, hex)
			elif hex_to_move:
				var piece_to_move = get_piece(hex_to_move)
				if piece_to_move:
					_play_selected(hex, hex_to_move) 
					
					if piece_to_move.use_manual_path:
						ui.show_stats(piece_to_move)
					else:
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
						var points = PackedVector2Array()
						var prev = piece.get_hex()
						
						points.append(grid.get_hex_pos(prev))
						for p in piece.movement_comp.path:
							points.append(grid.get_hex_pos(p))
							prev = p
						
						_ghost_grid()
						var mouse_points = grid.get_hex_path(prev, target_hex)
						_unghost_grid()
						
						for i in range(1, mouse_points.size()):
							points.append(mouse_points[i])
						path_line.points = points
					else:
						path_line.default_color = Color(0.5, 1.0, 0.2)
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
					if piece:
						grid.enable_hex(hex_to_move)
						piece.toggle_path_mode()
						ui.show_stats(piece)
			KEY_F:
				if hex_to_move:
					var piece = get_piece(hex_to_move)
					if piece and piece.is_combatant():
						piece.clear_attack_target()
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

# ── Day cycle ─────────────────────────────────────────────────────────────────

func _unfreeze_all():
	for unit in units:
		if is_instance_valid(unit):
			unit.unfreeze()

func clock_increment():
	day += 1
	ui.update_day(day)

	_unfreeze_all()
	card_manager.check_pending(day)
	enemy_ai.run_turn() 

	var starved = _resolve_all_movement()
	
	recent_death_hexes.clear() 
	_resolve_all_combat()

	for unit in units:
		unit.process_resupply()

	var card_to_play = card_manager.draw_daily_card(day)
	if card_to_play: 
		ui.card_ui.display_card(card_to_play)
	else: 
		ui.card_ui.hide()

	for city in cities:
		city.next_day()

	for dead in starved:
		print("%s starved." % dead.name)
		_die(dead)

	_unfreeze_all()
	fow_manager.update_fow()

	if ui.city_menu.visible: 
		ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock)
		
	if ui.panel.visible:
		ui.refresh_stats()

func _next_day_button():
	clock_increment()
