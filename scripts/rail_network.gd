extends Node
class_name RailNetwork

signal train_created(train: Node2D)
signal rail_broken(hex: Vector2i)
signal rail_repaired(hex: Vector2i)

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
const RAIL  = preload("res://scenes/rail.tscn")
const TRAIN = preload("res://scenes/train.tscn")

const REPAIR_COST: int = 50

var rail_hexes: Dictionary = {}        # hex -> { route_id, broken, node }
var rail_routes: Dictionary = {}       # route_id -> Array[Vector2i]
var route_trains: Dictionary = {}      # route_id -> Train node (null if none)
var next_route_id: int = 0
var building_route: Array = []
var rail_nodes_building: Dictionary = {}
var player_rail_stock: int  = 0
var player_train_stock: int = 0

var grid: Node
var terrain: Node2D
# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(_grid: Node, _terrain: Node2D):
	grid = _grid
	terrain = _terrain

# ── Rail Building ─────────────────────────────────────────────────────────────

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
	if grid.get_piece(hex) is City: return

	if terrain.is_mountain(hex) and not terrain.has_tunnel(hex):
		print("Cannot build rail on a mountain without a tunnel!")
		return

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
	rail_node.position = grid.get_hex_pos(hex)
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
	route_trains[id] = null

	_spawn_train_on_route(id)

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

# ── Rail Damage & Repair ──────────────────────────────────────────────────────

func break_rail_at(hex: Vector2i):
	if not rail_hexes.has(hex): return
	var entry = rail_hexes[hex]
	if entry["broken"]: return   # Already broken, no need to re-signal
	entry["broken"] = true
	var node = entry.get("node")
	if node and is_instance_valid(node):
		node.break_rail()
	rail_broken.emit(hex)
	print("Rail broken at %s" % str(hex))

func repair_rail_at(hex: Vector2i, logistics_unit: Node) -> bool:
	"""Repairs a broken rail hex. Costs REPAIR_COST from the logistics unit.
	Returns true if the repair succeeded."""
	if not rail_hexes.has(hex):
		return false
	var entry = rail_hexes[hex]
	if not entry["broken"]:
		print("Rail at %s is not broken." % str(hex))
		return false
	if logistics_unit.get_resources() < REPAIR_COST:
		print("Not enough supplies to repair rail (need %d)." % REPAIR_COST)
		return false

	logistics_unit.deplete(REPAIR_COST)
	entry["broken"] = false
	var node = entry.get("node")
	if node and is_instance_valid(node):
		node.repair_rail()
	rail_repaired.emit(hex)
	print("Rail repaired at %s" % str(hex))
	return true

# ── Train Deployment ──────────────────────────────────────────────────────────

func get_route_id_for_hex(hex: Vector2i) -> int:
	"""Returns the route_id the hex belongs to, or -1 if none."""
	if not rail_hexes.has(hex): return -1
	return rail_hexes[hex]["route_id"]

func has_train_on_route(route_id: int) -> bool:
	if not route_trains.has(route_id): return false
	var t = route_trains[route_id]
	return t != null and is_instance_valid(t)

func can_deploy_train(hex: Vector2i) -> bool:
	"""Returns true if the player could place a train at this rail hex."""
	var id = get_route_id_for_hex(hex)
	if id == -1: return false
	return not has_train_on_route(id)

func deploy_train_from_stock(hex: Vector2i) -> bool:
	"""Places a train on the route that contains hex, starting from route[0].
	Consumes one from player_train_stock. Returns true on success."""
	if player_train_stock < 1:
		print("No trains in stock."); return false
	var id = get_route_id_for_hex(hex)
	if id == -1:
		print("No route at that hex."); return false
	if has_train_on_route(id):
		print("Route already has a train."); return false

	_spawn_train_on_route(id)
	player_train_stock -= 1
	return true

func _spawn_train_on_route(route_id: int):
	var train = TRAIN.instantiate()
	add_child(train, true)
	train.setup_route(rail_routes[route_id], route_id, grid, self)
	route_trains[route_id] = train
	# When the train is freed (e.g. destroyed), clear its slot so the route can be reused.
	train.tree_exiting.connect(func(): _on_train_removed(route_id))
	train_created.emit(train)

func _on_train_removed(route_id: int):
	if route_trains.has(route_id):
		route_trains[route_id] = null
