extends Node2D
class_name Movement

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var piece: Node2D
var hex = null               # null until the piece is placed on the board

func get_hex(): return hex

func _ready():
	piece = get_parent()

# ── Moving Hex ────────────────────────────────────────────────────────────────

func set_hex(new_hex, grid):
	"""Places the piece on new_hex and updates the grid references."""
	grid.set_piece(new_hex, piece)
	if hex != null:
		grid.set_piece(hex)        # clear the old cell
	hex = new_hex
	piece.position = grid.get_hex_pos(new_hex)

func force_hex(new_hex, grid):
	"""Sets hex, bypassing adjacency checks (trains, teleports)."""
	if hex != null:
		grid.set_piece(hex)
	hex = new_hex
	grid.set_piece(new_hex, piece)
	piece.position = grid.get_hex_pos(new_hex)

func move_to(new_hex, grid) -> bool:
	"""One-step move. Initial placement is free; afterwards a move must be to an
	adjacent empty hex and spends the piece's daily action (freeze)."""
	if not grid.Grid.has(new_hex):
		return false

	# Initial placement does not freeze
	if hex == null:
		if grid.get_piece(new_hex) != null:
			return false
		set_hex(new_hex, grid)
		return true

	if piece.is_frozen():
		return false
	if not (new_hex in HEX.axial_neighbours(hex)):
		return false
	if grid.get_piece(new_hex) != null:
		return false

	grid.disable_hex(new_hex)
	set_hex(new_hex, grid)
	piece.freeze()
	return true

# ── Pathing ───────────────────────────────────────────────────────────────────

var goal = null              # auto-goal: re-routes around traffic each day
var path: Array = []         # manual path: strict list of hexes to walk

func set_goal(target_hex):
	path.clear()
	goal = target_hex

func add_waypoint(target_hex):
	goal = null
	path.append(target_hex)

func clear_movement():
	goal = null
	path.clear()

func process_movement(grid):
	"""Walks one step along the manual path, or one step toward the auto-goal."""
	if path.size() > 0:
		_manual_pathing(grid)
	elif goal != null:
		_auto_pathing(grid)

func _auto_pathing(grid):
	var current = get_hex()
	if current == goal:
		clear_movement()
		return

	# Treat friendly traffic as passable to get the ideal A* route
	var passable = [current, goal]
	for h in grid.Grid:
		var p = grid.get_piece(h)
		if p and p.has_method("is_combatant") and not (p is City):
			passable.append(h)

	grid.sync_pathing(passable)
	var astar_path = grid.get_map_path(current, goal)
	grid.sync_pathing()

	if astar_path.size() > 1:
		var next_hex = astar_path[1]
		var piece_in_way = grid.get_piece(next_hex)

		if piece_in_way == null:
			move_to(next_hex, grid)
		elif piece_in_way is City:
			clear_movement()   # arrived next to the target city, or blocked by one
		elif piece_in_way.team != piece.team:
			clear_movement()   # enemy in the way: stop and let the player decide

func _manual_pathing(grid):
	var next_hex = path[0]
	var piece_in_way = grid.get_piece(next_hex)

	if piece_in_way == null:
		if move_to(next_hex, grid):
			path.pop_front()
	elif piece_in_way is City:
		clear_movement()
	elif piece_in_way.team != piece.team:
		clear_movement()
	# Friendly unit in the way: hold position this turn, try again tomorrow.
