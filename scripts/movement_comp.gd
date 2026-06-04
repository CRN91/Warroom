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
	# Hex exists in grid
	if HEX.axial_to_oddr(check_hex) in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
		# Hex is a neighbour of the current hex
		if hex:
			if check_hex in HEX.axial_neighbours(hex):
				# Hex occupied status
				return not grid.get_piece(check_hex)
		else:
			return not grid.get_piece(check_hex)
	else:
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
		grid.disable_hex(new_hex)
		set_hex(new_hex, grid)
		return

	var frozen = piece.frozen
	if not frozen:
		frozen = true
		grid.enable_hex(old_hex)

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
				grid.disable_hex(old_hex)
		else:
			frozen = false
			grid.disable_hex(old_hex)
	piece.frozen = frozen

# ── Pathing ───────────────────────────────────────────────────────────

# Auto
var goal
func set_goal(hex): goal = hex
func clear_goal(): goal = null

# Manual
var path: Array = []
func add_waypoint(hex): path.append(hex)
func clear_path(): path.clear()

func process_movement(grid):
	"""Decides pathing type used"""
	if path.size() > 0:
		_manual_pathing(grid)
	elif goal:
		_auto_pathing(grid)

func _auto_pathing(grid):
	var current_hex = get_hex()
	if current_hex == goal:
		clear_goal()
	else:
		var goal_piece = grid.get_piece(goal)
		grid.enable_hex(current_hex)
		if goal_piece: grid.enable_hex(goal)

		var hidden_hexes = []
		for hex in grid.Grid:
			var temp_piece = grid.get_piece(hex)
			if temp_piece and not temp_piece.visible and temp_piece.team != piece.team:
				grid.enable_hex(hex)
				hidden_hexes.append(hex)

		var astar_path = grid.get_map_path(current_hex, goal)

		# Re-disable the hidden enemies to restore the grid state
		for h in hidden_hexes:
			grid.disable_hex(h)

		grid.disable_hex(current_hex)
		if goal_piece: grid.disable_hex(goal)

		if astar_path.size() > 1:
			move_to(astar_path[1], grid)

func _manual_pathing(grid):
	var next_hex = path[0]
	if grid.get_piece(next_hex) == null:
		move_to(next_hex, grid)
		path.pop_front()
