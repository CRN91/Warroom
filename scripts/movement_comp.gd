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

	var old_hex = hex
	grid.disable_hex(new_hex)
	set_hex(new_hex, grid)
	piece.freeze()
	_withdrawal_fire(old_hex, new_hex, grid)
	return true

func _withdrawal_fire(old_hex, new_hex, grid) -> void:
	## Disengaging from contact has a price: one adjacent enemy combatant gets
	## a parting shot (half damage) if the move breaks out of its reach.
	for adj in HEX.axial_neighbours(old_hex):
		if not grid.Grid.has(adj): continue
		var e = grid.get_piece(adj)
		if e == null or e.team == piece.team: continue
		if not (e.has_method("is_combatant") and e.is_combatant()): continue
		if HEX.axial_distance(e.get_hex(), new_hex) <= 1: continue  # still in contact — no shot

		var dmg = int(round(e.get_damage() * 0.5))
		if dmg > 0:
			piece.deplete(dmg)
			if piece.team == 1:
				Events.notify("%s took %d withdrawal fire from %s." % [piece.name, dmg, e.name])
		return

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

	# 1. Prefer a route around other units (true collisions, just allow the goal)
	grid.sync_pathing([current, goal])
	var astar_path = grid.get_map_path(current, goal)
	grid.sync_pathing()

	# 2. If fully boxed in, fall back to the through-traffic route and wait in line
	if astar_path.size() < 2:
		var passable = [current, goal]
		for h in grid.Grid:
			var p = grid.get_piece(h)
			if p and p.has_method("is_combatant") and not (p is City):
				passable.append(h)
		grid.sync_pathing(passable)
		astar_path = grid.get_map_path(current, goal)
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
		# Friendly unit in the way: hold this turn; a later movement pass (or
		# tomorrow) will find the hex free or route around it.

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
