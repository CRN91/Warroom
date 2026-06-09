extends Node2D

class_name Movement

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var piece: Node2D
var hex: Vector2i
func get_hex(): return hex

func _ready():
	piece = get_parent()

# ── Moving Hex ───────────────────────────────────────────────────────────

func valid_hex(check_hex, grid):
	""" Checks the hex exists, is adjacent and is not occupied """
	
	if grid.Grid.has(check_hex):
		if hex:
			if check_hex in HEX.axial_neighbours(hex):
				return grid.get_piece(check_hex) == null
		else:
			return grid.get_piece(check_hex) == null

	return false
		
func set_hex(new_hex, grid):
	""" Sets the position of the object on the grid.
	Assumes the tile coords are given in axial or cube.
	'old_loc' is used when the piece is already set and being moved. """
	if valid_hex(new_hex, grid):
		# Gets the centered position of the hex
		var pos = grid.get_hex_pos(new_hex)

		# Sets a reference to the parent node in the grid
		grid.set_piece(new_hex, piece)
		
		# If the piece is currently stored somewhere, removes the reference
		if hex:
			grid.set_piece(hex)
			
		hex = new_hex
		piece.position = pos

func force_hex(new_hex, grid):
	"""Sets Hex but bypasses adjacency checks"""
	if hex:
		grid.set_piece(hex)
	hex = new_hex
	grid.set_piece(new_hex, piece)
	piece.position = grid.get_hex_pos(new_hex)

func move_to(new_hex, grid):
	var old_hex = get_hex()
	# Inital placement does not freeze
	if not old_hex:
		#grid.disable_hex(new_hex)
		set_hex(new_hex, grid)
		return

	var frozen = piece.frozen
	if not frozen:
		frozen = true
		#grid.enable_hex(old_hex)

		# Adjacency check
		if new_hex in HEX.axial_neighbours(old_hex):
			if grid.get_piece(new_hex) == null:
				grid.disable_hex(new_hex)
				set_hex(new_hex, grid)
				piece.frozen = frozen
				return
			else:
				# Hex occupied
				frozen = false
				#grid.disable_hex(old_hex)
		else:
			frozen = false
			#grid.disable_hex(old_hex)
	piece.frozen = frozen

# ── Pathing ───────────────────────────────────────────────────────────

var goal = null
var path: Array = []

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
	"""Decides pathing type used"""
	if path.size() > 0:
		_manual_pathing(grid)
	elif goal != null:
		_auto_pathing(grid)

func _auto_pathing(grid):
	var current = get_hex()
	if current == goal:
		clear_movement()
		return

	# Treat all units as passable to get inital A* route
	var passable = [current, goal]
	for h in grid.Grid:
		var p = grid.get_piece(h)
		if p and p.has_method("is_combatant") and not (p is City):
			passable.append(h)

	grid.sync_pathing(passable)
	var astar_path = grid.get_map_path(current, goal)
	grid.sync_pathing()

	# Attempt the move
	if astar_path.size() > 1:
		var next_hex = astar_path[1]
		var piece_in_way = grid.get_piece(next_hex)

		if piece_in_way == null:
			move_to(next_hex, grid)
		elif piece_in_way is City:
			if HEX.axial_distance(current, goal) == 1 and goal == next_hex:
				clear_movement() # We arrived next to our target city
			else:
				clear_movement() # Path blocked by unexpected city
		elif piece_in_way.team != piece.team:
			clear_movement() 

func _manual_pathing(grid):
	var next_hex = path[0]
	var piece_in_way = grid.get_piece(next_hex)

	if piece_in_way == null:
		move_to(next_hex, grid)
		path.pop_front()
	elif piece_in_way is City:
		clear_movement()
	elif piece_in_way.team != piece.team:
		clear_movement()
