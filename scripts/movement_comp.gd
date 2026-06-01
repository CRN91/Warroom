extends Node2D

class_name Movement

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var piece: Node2D
var hex

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
	
	var pos

	# Checks if Vector3 (cube)
	if typeof(new_hex) == 7:
		new_hex = Vector2i(new_hex.x, new_hex.y) # Converts to axial

	# Moves to new position if a valid hex
	if valid_hex(new_hex, grid):
		# Gets the centered position of the hex
		pos = grid.map_to_local(HEX.axial_to_oddr(new_hex))

		# Sets a reference to the parent node in the grid
		grid.set_piece(new_hex, piece)
		
		# If the piece is currently stored somewhere, removes the reference
		if hex:
			grid.set_piece(hex)
			
		hex = new_hex
		piece.position = pos
		
	# Returns the grid so we have one central location where all pieces are referenced
	return grid

## Bypasses adjacency and occupancy checks.
## Used by Train which manages its own route validation.
func force_hex(new_hex, grid):
	if typeof(new_hex) == 7:
		new_hex = Vector2i(new_hex.x, new_hex.y)
	if hex:
		grid.set_piece(hex)
	hex = new_hex
	grid.set_piece(new_hex, piece)
	piece.position = grid.map_to_local(HEX.axial_to_oddr(new_hex))
	return grid

func get_hex():
	return hex

func _ready():
	piece = get_parent()
