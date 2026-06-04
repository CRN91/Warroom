extends Node
class_name RailNetwork

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
const RAIL = preload("res://scenes/rail.tscn")
const TRAIN = preload("res://scenes/train.tscn")

var rail_hexes: Dictionary = {}
var rail_routes: Dictionary = {}
var next_route_id: int = 0
var building_route: Array = []
var rail_nodes_building: Dictionary = {}
var player_rail_stock: int  = 0
var player_train_stock: int = 0

var game: Node2D # Reference to Game.gd to access grid, stocks, and unit arrays

func setup(_game: Node2D):
	game = _game

func toggle_rail(hex):
	if hex in building_route:
		var is_back  = hex == building_route.back()
		var is_front = hex == building_route.front()
		if is_back or is_front:
			if is_back: building_route.pop_back()
			else:       building_route.pop_front()
			if rail_nodes_building.has(hex):
				rail_nodes_building[hex].queue_free()
				rail_nodes_building.erase(hex)
			player_rail_stock += 1
		else:
			print("Can only remove from either end")
		return

	if rail_hexes.has(hex): return
	if game.get_piece(hex) is City: return

	if player_rail_stock < 1:
		print("Not enough rail stock"); return

	if building_route.size() > 0:
		var to_back  = hex in HEX.axial_neighbours(building_route.back())
		var to_front = hex in HEX.axial_neighbours(building_route.front())
		if not to_back and not to_front:
			print("Hex must be adjacent to either end"); return

	var rail_node = RAIL.instantiate()
	add_child(rail_node)
	rail_node.hex_pos  = hex
	rail_node.position = game._hex_to_pos(hex)
	rail_node.modulate = Color(0.6, 0.6, 1.0)

	if building_route.size() > 0 and hex in HEX.axial_neighbours(building_route.back()):
		building_route.append(hex)
	else:
		building_route.insert(0, hex)

	rail_nodes_building[hex] = rail_node
	player_rail_stock -= 1

func commit_rail_route():
	if building_route.size() < 2:
		print("Need at least 2 hexes"); return
	if player_train_stock < 1:
		print("Need at least 1 train in stock"); return

	var id = next_route_id
	next_route_id += 1
	for hex in building_route:
		var rn = rail_nodes_building[hex]
		rn.modulate = Color(1.0, 1.0, 1.0)
		rail_hexes[hex] = { "route_id": id, "broken": false, "node": rn }
	rail_routes[id] = building_route.duplicate()

	var train = TRAIN.instantiate()
	add_child(train, true)
	train.setup_route(rail_routes[id], id, game.grid, self)
	game.trains.append(train); game.units.append(train)
	player_train_stock -= 1
	building_route.clear()
	rail_nodes_building.clear()

func cancel_rail_build():
	player_rail_stock += building_route.size()
	for hex in building_route:
		if rail_nodes_building.has(hex):
			rail_nodes_building[hex].queue_free()
	building_route.clear()
	rail_nodes_building.clear()
