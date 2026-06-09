extends Node
class_name RailNetwork

## Rail building, damage/repair, and train deployment.
## Routes are planned hex by hex (R key), then committed (T key) which spawns a
## train from stock. Broken rail halts trains until your Engineers repair it.
## Rail can only be planned on hexes adjacent to an Engineers unit, and may
## only cross a river where a bridge already stands.

signal train_created(train: Node2D)

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
const TRAIN = preload("res://scenes/train.tscn")
const RAIL  = preload("res://scenes/rail.tscn")

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

func setup(_grid: Node, _terrain: Node2D):
	grid = _grid
	terrain = _terrain

# ── Rail building ─────────────────────────────────────────────────────────────

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
			Events.notify("Rail can only be removed from either end of the plan.")
		return

	if rail_hexes.has(hex): return
	if grid.get_piece(hex) is City: return

	if terrain.is_mountain(hex) and not terrain.has_tunnel(hex):
		Events.notify("Cannot lay rail on a mountain without a tunnel.")
		return

	if player_rail_stock < 1:
		Events.notify("No rail in stock.")
		return

	if not _engineer_nearby(hex):
		Events.notify("Rail must be laid near your Engineers.")
		return

	if building_route.size() > 0:
		var to_back  = _can_link(building_route.back(), hex)
		var to_front = _can_link(building_route.front(), hex)
		if not to_back and not to_front:
			if hex in HEX.axial_neighbours(building_route.back()) or hex in HEX.axial_neighbours(building_route.front()):
				Events.notify("A rail crossing needs a bridge on that river first.")
			else:
				Events.notify("Rail must extend from either end of the plan.")
			return
		if to_back:
			building_route.append(hex)
		else:
			building_route.insert(0, hex)
	else:
		building_route.append(hex)

	var rail_node = RAIL.instantiate()
	add_child(rail_node)
	rail_node.hex_pos  = hex
	rail_node.position = grid.get_hex_pos(hex)
	rail_node.modulate = Color(0.6, 0.6, 1.0)   # blue tint = planned, not committed

	rail_nodes_building[hex] = rail_node
	player_rail_stock -= 1

func _can_link(a: Vector2i, b: Vector2i) -> bool:
	## Two rail hexes can connect if adjacent and not split by an unbridged river.
	if not (b in HEX.axial_neighbours(a)):
		return false
	return terrain.is_crossable(a, b)

func _engineer_nearby(hex: Vector2i) -> bool:
	## Rails are laid by Engineers: the hex (or a neighbour) must hold one.
	for h in [hex] + HEX.axial_neighbours(hex):
		if not grid.Grid.has(h): continue
		var p = grid.get_piece(h)
		if p and p.team == 1 and p is Engineers:
			return true
	return false

func commit_rail_route():
	if building_route.is_empty():
		return

	# Extending an existing line? (plan touches a terminus of a committed route)
	var ext: Dictionary = _find_extension()
	if not ext.is_empty():
		_commit_extension(ext["route_id"], ext["merged"])
		return

	if building_route.size() < 2:
		Events.notify("A new rail route needs at least 2 hexes.")
		return
	if player_train_stock < 1:
		Events.notify("Need a train in stock to open a new line.")
		return

	var id = next_route_id
	next_route_id += 1
	for hex in building_route:
		var rn = rail_nodes_building[hex]
		rn.modulate = Color(1.0, 1.0, 1.0)
		rail_hexes[hex] = { "route_id": id, "broken": false, "node": rn }
	rail_routes[id] = building_route.duplicate()
	route_trains[id] = null

	if _spawn_train_on_route(id):
		player_train_stock -= 1
	building_route.clear()
	rail_nodes_building.clear()

	Events.notify("Rail line opened.")
	Events.rail_established.emit(id)

func _find_extension() -> Dictionary:
	## If the planned strip links (bridge-checked) to the end of an existing
	## route, return that route id plus the merged hex list.
	for id in rail_routes:
		var r: Array = rail_routes[id]
		if r.is_empty(): continue
		if _can_link(r.back(), building_route.front()):
			return { "route_id": id, "merged": r + building_route }
		if _can_link(r.back(), building_route.back()):
			var rev := building_route.duplicate(); rev.reverse()
			return { "route_id": id, "merged": r + rev }
		if _can_link(r.front(), building_route.front()):
			var rev2 := building_route.duplicate(); rev2.reverse()
			return { "route_id": id, "merged": rev2 + r }
		if _can_link(r.front(), building_route.back()):
			return { "route_id": id, "merged": building_route + r }
	return {}

func _commit_extension(route_id: int, merged: Array) -> void:
	for hex in building_route:
		var rn = rail_nodes_building[hex]
		rn.modulate = Color(1.0, 1.0, 1.0)
		rail_hexes[hex] = { "route_id": route_id, "broken": false, "node": rn }

	rail_routes[route_id] = merged
	var t = route_trains.get(route_id)
	if t != null and is_instance_valid(t):
		t.route = merged   # the running train learns the longer line

	building_route.clear()
	rail_nodes_building.clear()
	Events.notify("Rail line extended.")

func cancel_rail_build():
	player_rail_stock += building_route.size()
	for hex in building_route:
		if rail_nodes_building.has(hex):
			rail_nodes_building[hex].queue_free()
	building_route.clear()
	rail_nodes_building.clear()

# ── Rail damage & repair ──────────────────────────────────────────────────────

func break_rail_at(hex: Vector2i):
	if not rail_hexes.has(hex): return
	var entry = rail_hexes[hex]
	if entry["broken"]: return
	entry["broken"] = true
	var node = entry.get("node")
	if node and is_instance_valid(node):
		node.break_rail()
	Events.rail_broken.emit(hex)
	Events.notify("Rail broken at %s." % str(hex))

func repair_rail_at(hex: Vector2i, logistics_unit: Node) -> bool:
	"""Repairs a broken rail hex. Costs REPAIR_COST from the logistics unit."""
	if not rail_hexes.has(hex):
		return false
	var entry = rail_hexes[hex]
	if not entry["broken"]:
		return false
	if logistics_unit.get_resources() < REPAIR_COST:
		Events.notify("Not enough supplies to repair rail (need %d)." % REPAIR_COST)
		return false

	logistics_unit.deplete(REPAIR_COST)
	entry["broken"] = false
	var node = entry.get("node")
	if node and is_instance_valid(node):
		node.repair_rail()
	Events.rail_repaired.emit(hex)
	Events.notify("Rail repaired.")
	return true

# ── Train deployment ──────────────────────────────────────────────────────────

func get_route_id_for_hex(hex: Vector2i) -> int:
	if not rail_hexes.has(hex): return -1
	return rail_hexes[hex]["route_id"]

func has_train_on_route(route_id: int) -> bool:
	if not route_trains.has(route_id): return false
	var t = route_trains[route_id]
	return t != null and is_instance_valid(t)

func can_deploy_train(hex: Vector2i) -> bool:
	var id = get_route_id_for_hex(hex)
	if id == -1: return false
	return not has_train_on_route(id)

func deploy_train_from_stock(hex: Vector2i) -> bool:
	"""Places a train on the route containing hex, starting from route[0].
	Consumes one from player_train_stock."""
	if player_train_stock < 1:
		Events.notify("No trains in stock.")
		return false
	var id = get_route_id_for_hex(hex)
	if id == -1: return false
	if has_train_on_route(id):
		Events.notify("That line already has a train.")
		return false

	if not _spawn_train_on_route(id):
		return false
	player_train_stock -= 1
	return true

func _spawn_train_on_route(route_id: int) -> bool:
	# Deploy at the first unoccupied hex of the route (normally terminus A).
	var start_hex = null
	for h in rail_routes[route_id]:
		if grid.get_piece(h) == null:
			start_hex = h
			break
	if start_hex == null:
		Events.notify("No free hex on the line to deploy a train.")
		return false

	var train = TRAIN.instantiate()
	add_child(train, true)
	train.setup_route(rail_routes[route_id], route_id, grid, self, start_hex)
	route_trains[route_id] = train
	# When the train is freed (e.g. destroyed), clear its slot so the route can be reused.
	train.tree_exiting.connect(func(): _on_train_removed(route_id))
	train_created.emit(train)
	return true

func _on_train_removed(route_id: int):
	if route_trains.has(route_id):
		route_trains[route_id] = null
