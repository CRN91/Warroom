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
@onready var modifiers: ModifierManager = $ModifierManager
@onready var terrain_manager = $TerrainManager

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
	"bridge":    400,
	"tunnel":    800 
}

var game_state: Dictionary = { "move_cost": 1, "attack_modifier": 1.0, "weather": "clear" }
var pending_cards: Array    = []
var pending_restores: Array = []
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
	
	terrain_manager.setup(grid)
	grid.terrain = terrain_manager
	var terrain_options = {
		"hq_hexes": [Vector2i(0, 3), Vector2i(0, -3)],
		"city_hexes": [Vector2i(0, 0)], 
		"occupied": [Vector2i(2, 1), Vector2i(1, -3), Vector2i(2, -3), Vector2i(-1, 2), Vector2i(-1, -1)]
	}
	terrain_manager.generate(terrain_options)
	
	rail_network.setup(grid, terrain_manager)
	rail_network.train_created.connect(_on_train_created)
	
	ui.setup(COST)
	ui.next_day_requested.connect(clock_increment)
	ui.buy_requested.connect(_on_city_buy_requested)
	ui.card_choice_made.connect(card_manager.resolve_choice)
	
	test_setup()

	for u in units:
		if is_instance_valid(u): u.game = self
	for c in cities:
		if is_instance_valid(c): c.game = self

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
	train.game = self
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
	elif item_type == "bridge":
		terrain_manager.bridge_stock += 1
		purchased = true
	elif item_type == "tunnel": 
		terrain_manager.tunnel_stock += 1
		purchased = true
	else:
		var scene = {"infantry": INFANTRY, "artillery": ARTILLERY, "logistics": LOGI}[item_type]
		purchased = _spawn_unit_near_city(scene, city, item_type)

	if purchased:
		city.deplete(cost)
		ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock, terrain_manager.bridge_stock, terrain_manager.tunnel_stock)
		
func _spawn_unit_near_city(scene: PackedScene, city: Node2D, unit_type: String = "") -> bool:
	for adj in HEX.axial_neighbours(city.get_hex()):
		if not grid.Grid.has(adj): continue
		
		if get_piece(adj) == null and not rail_network.rail_hexes.has(adj) and not adj in recent_death_hexes:
			if terrain_manager.is_mountain(adj): continue # Prevents spawning units inside mountains
			
			var unit = scene.instantiate()
			unit.setup(grid)
			add_child(unit, true)
			unit.game = self
			if unit_type != "": unit.unit_type = unit_type
			
			if city.team == 2: 
				unit.set_enemy()
				
			unit.move_to(adj)
			units.append(unit)
			fow_manager.update_fow()
			return true
		
	print("No free hex adjacent to %s" % city.name)
	return false

# ── Card-driven board changes ─────────────────────────────────────────────────

func spawn_unit(effect: Dictionary) -> Node2D:
	var type: String = effect.get("unit", "infantry")
	var team: int    = int(effect.get("team", 1))
	var scene: PackedScene = {
		"infantry": INFANTRY, "artillery": ARTILLERY, "logistics": LOGI
	}.get(type, INFANTRY)

	var hex = _resolve_spawn_hex(effect.get("near", "player_hq"))
	if hex == null:
		print("spawn_unit: no free hex for %s" % type)
		return null

	var unit = scene.instantiate()
	unit.setup(grid)
	add_child(unit, true)
	unit.game = self
	unit.unit_type = effect.get("unit_type", type)
	if team == 2: unit.set_enemy()

	if effect.has("name"):           unit.name = effect["name"]
	if effect.has("tags"):           unit.tags = effect["tags"].duplicate()
	if effect.has("max_resources"):  unit.resource_comp.set_max_resources(int(effect["max_resources"]))
	if effect.get("fill", false):    unit.replenish(unit.get_max_resources())

	unit.move_to(hex)
	units.append(unit)

	for m in effect.get("modifiers", []):
		var mm: Dictionary = m.duplicate(true)
		mm["scope"] = "unit:%d" % unit.get_instance_id()
		modifiers.add_modifier(mm)

	fow_manager.update_fow()
	return unit

func transform_units(effect: Dictionary) -> void:
	var scope: String = effect.get("scope", "player")
	var pieces: Array = modifiers.select_pieces(units, cities, scope)
	if effect.get("combatants_only", false):
		pieces = pieces.filter(func(p): return p.has_method("is_combatant") and p.is_combatant())
	var count: int = int(effect.get("count", 1))

	var done := 0
	for p in pieces:
		if done >= count: break
		if effect.has("unit_type"):     p.unit_type = effect["unit_type"]
		if effect.has("rename"):        p.name = effect["rename"]
		if effect.has("add_tags"):      p.tags.append_array(effect["add_tags"])
		if effect.has("max_resources"): p.resource_comp.set_max_resources(int(effect["max_resources"]))
		if effect.has("set_resources"): p.resource_comp.resources = int(effect["set_resources"])
		if effect.has("replenish"):     p.replenish(int(effect["replenish"]))
		for m in effect.get("modifiers", []):
			var mm: Dictionary = m.duplicate(true)
			mm["scope"] = "unit:%d" % p.get_instance_id()
			modifiers.add_modifier(mm)
		p.update_ui()
		done += 1

# ── Spawn-location helpers ────────────────────────────────────────────────────

func _resolve_spawn_hex(near):
	var center
	if near is Array and near.size() == 2:
		center = Vector2i(int(near[0]), int(near[1]))
		if get_piece(center) == null and grid.Grid.has(center):
			return center
	elif near == "player_hq":
		var hq = player_hq()
		center = hq.get_hex() if hq else null
	elif near == "enemy_hq":
		var hq = enemy_hq()
		center = hq.get_hex() if hq else null
	else:
		var c = find_city_by_name(str(near))
		center = c.get_hex() if c else null

	if center == null:
		return null
	return _free_hex_near(center)

func _free_hex_near(center: Vector2i):
	for adj in HEX.axial_neighbours(center):
		if not grid.Grid.has(adj): continue
		if get_piece(adj) == null and not rail_network.rail_hexes.has(adj) and not adj in recent_death_hexes:
			if terrain_manager.is_mountain(adj): continue
			return adj
	return null

func find_city_by_name(n: String) -> Node2D:
	for c in cities:
		if c.name == n: return c
	return null

func player_hq() -> Node2D:
	for c in cities:
		if c.is_hq and c.team == 1: return c
	return null

func enemy_hq() -> Node2D:
	for c in cities:
		if c.is_hq and c.team == 2: return c
	return null

# ── Selection ─────────────────────────────────────────────────────────────────

func _select_piece(piece: Node2D, hex: Vector2i):
	if piece is City:
		if piece.team == 1:
			ui.open_city_menu(piece, rail_network.player_rail_stock, rail_network.player_train_stock, terrain_manager.bridge_stock, terrain_manager.tunnel_stock)
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

		var target_hex = target.get_hex()
		if target_hex and rail_network.rail_hexes.has(target_hex):
			rail_network.break_rail_at(target_hex)
			
		if attacker.get_resources() <= 0 and attacker not in to_die:
			to_die.append(attacker)

	for dead in to_die:
		if is_instance_valid(dead):
			_die(dead)

# ── Movement ──────────────────────────────────────────────────────────────────

func _resolve_all_movement() -> Array:
	var starved: Array = []
	
	var player_manual = []
	var player_auto = []
	var enemy_units = []

	for unit in units:
		if unit is City: continue
		
		if unit.team == 1:
			if unit.get("use_manual_path"):
				player_manual.append(unit)
			else:
				player_auto.append(unit)
		else:
			enemy_units.append(unit)

	var ordered_units = player_manual + player_auto + enemy_units

	for unit in ordered_units:
		var blocked := modifiers != null and modifiers.is_movement_blocked(unit)
		if unit.has_method("process_movement") and not blocked:
			unit.process_movement()

		if unit.next_day():
			starved.append(unit)

	return starved

func _handle_movement_command(unit, target_hex):
	if unit.use_manual_path:
		var start_hex = unit.movement_comp.path.back() if unit.movement_comp.path.size() > 0 else unit.get_hex()

		grid.sync_pathing(_occupied_hexes()) 
		var route = grid.get_map_path(start_hex, target_hex)
		grid.sync_pathing()   

		for i in range(1, route.size()):
			unit.movement_comp.add_waypoint(route[i])
	else:
		unit.movement_comp.set_goal(target_hex)

func _play_selected(hex, p_hex_to_move):
	var selected    = get_piece(hex)
	var active_unit = get_piece(p_hex_to_move)
	if not active_unit: return

	# ── Logistics repair / build action ───────────────────────────────────────
	if active_unit is Logistics:
		var dist = HEX.axial_distance(p_hex_to_move, hex)
		if dist == 1:
			var acted = false
			
			# 1. Build Tunnel (Clicking a mountain without a tunnel)
			if terrain_manager.is_mountain(hex) and not terrain_manager.has_tunnel(hex):
				if terrain_manager.tunnel_stock > 0:
					terrain_manager.build_tunnel(hex)
					terrain_manager.tunnel_stock -= 1
					acted = true
					
			# 2. Build Bridge (Clicking across a river edge)
			elif terrain_manager.is_river_edge(p_hex_to_move, hex) and not terrain_manager.is_bridged(p_hex_to_move, hex):
				if terrain_manager.bridge_stock > 0:
					terrain_manager.build_bridge(p_hex_to_move, hex)
					terrain_manager.bridge_stock -= 1
					acted = true
					
			# 3. Repair broken rail (Clicking a broken rail hex)
			elif not selected and rail_network.rail_hexes.has(hex) and rail_network.rail_hexes[hex]["broken"]:
				rail_network.repair_rail_at(hex, active_unit)
				acted = true
				
			if acted:
				if ui.city_menu.visible: 
					ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock, terrain_manager.bridge_stock, terrain_manager.tunnel_stock)
				return

	if active_unit.use_manual_path:
		if not selected is City:
			_handle_movement_command(active_unit, hex)
		return

	var click_as_empty = (not selected) or (not selected.visible and selected.team != active_unit.team)

	if click_as_empty:
		_handle_movement_command(active_unit, hex)
		#grid.enable_hex(p_hex_to_move) 
		return

	var dist = HEX.axial_distance(p_hex_to_move, hex)

	if active_unit.team != selected.team:
		if active_unit.is_combatant() and dist <= active_unit.get_attack_range():
			if dist > 1 and terrain_manager.blocks_line_of_fire(p_hex_to_move, hex):
				print("Line of fire blocked by mountain!")
			else:
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

	_cull_dead_units()

# ── Death ─────────────────────────────────────────────────────────────────────

func _cull_dead_units():
	var to_die = []
	for unit in units:
		if is_instance_valid(unit) and not (unit is City):
			if unit.get_resources() <= 0:
				to_die.append(unit)
				
	for dead in to_die:
		if is_instance_valid(dead):
			_die(dead)

func _die(dead_piece):
	for unit in units:
		if is_instance_valid(unit) and unit.get("attack_comp") and unit.get_attack_target() == dead_piece:
			unit.set_attack_target(null)

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
	dead_piece.queue_free()

func _game_over(player_lost: bool):
	ui.show_game_over(player_lost)
	get_tree().paused = true

func get_piece(hex): 
	return grid.get_piece(hex)
	
func set_piece(hex, piece=null): 
	grid.set_piece(hex, piece)

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event):
	if (event is InputEventMouse or event is InputEventMouseButton) and ui.is_mouse_over_ui():
		return
		
	if event.is_action_pressed("select"):
		var oddr_hex = grid.base_layer.local_to_map(get_global_mouse_position())
		var hex      = HEX.oddr_to_axial(oddr_hex)
		
		if hex in grid.Grid.keys():
			grid.select_hex(oddr_hex)
			var selected = get_piece(hex)
			
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
					
					if is_instance_valid(piece_to_move):
						if piece_to_move.use_manual_path:
							ui.show_stats(piece_to_move)
						else:
							_deselect_piece()
					else:
						_deselect_piece()

	elif event.is_action_pressed("deselect"):
		_deselect_piece()

	elif event is InputEventMouseMotion:
		if hex_to_move:
			var oddr_hex   = grid.base_layer.local_to_map(get_global_mouse_position())
			var target_hex = HEX.oddr_to_axial(oddr_hex)
			
			if target_hex in grid.Grid.keys():
				var piece = get_piece(hex_to_move)
				if piece:
					if piece.use_manual_path:
						path_line.default_color = Color(1.0, 0.8, 0.2)
						var points = PackedVector2Array()        # pixel positions — for the line only
						var prev = piece.get_hex()

						points.append(grid.get_hex_pos(prev))
						for p in piece.movement_comp.path:
							points.append(grid.get_hex_pos(p))
							prev = p

						grid.sync_pathing(_occupied_hexes())     # HEX coords, not pixels
						var mouse_points = grid.get_hex_path(prev, target_hex)
						grid.sync_pathing()                       # restore truth

						for i in range(1, mouse_points.size()):
							points.append(mouse_points[i])
						path_line.points = points
					else:
						path_line.default_color = Color(0.5, 1.0, 0.2)
						grid.sync_pathing([hex_to_move])
						path_line.points = grid.get_hex_path(hex_to_move, target_hex)
						grid.sync_pathing()
			else:
				path_line.clear_points()
		else:
			path_line.clear_points()

	elif event is InputEventKey and event.pressed and not event.echo:
		var oddr_hex = grid.base_layer.local_to_map(get_global_mouse_position())
		var hex      = HEX.oddr_to_axial(oddr_hex)

		match event.keycode:
			KEY_M:
				if hex_to_move:
					var piece = get_piece(hex_to_move)
					if piece:
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

func _occupied_hexes() -> Array:
	var out: Array = []
	for h in grid.Grid:
		var p = get_piece(h)
		if p and not (p is City):
			out.append(h)
	return out

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
		if is_instance_valid(unit):
			unit.process_resupply()

	var card_to_play = card_manager.draw_daily_card(day)
	if card_to_play:
		card_manager.resolve_drawn(card_to_play)   
		ui.card_ui.display_card(card_to_play)
	else: 
		ui.card_ui.hide()

	for city in cities:
		if is_instance_valid(city):
			city.next_day()

	for dead in starved:
		if is_instance_valid(dead):
			print("%s starved." % dead.name)
			_die(dead)

	_cull_dead_units()

	_unfreeze_all()
	fow_manager.update_fow()
	ui.update_debug(modifiers, game_state)

	if ui.city_menu.visible: 
		ui.refresh_city_menu(rail_network.player_rail_stock, rail_network.player_train_stock, terrain_manager.bridge_stock, terrain_manager.tunnel_stock)
		
	if ui.panel.visible:
		ui.refresh_stats()

func _next_day_button():
	clock_increment()
