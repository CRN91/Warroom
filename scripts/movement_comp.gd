extends Node2D

class_name Movement

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@export var piece: Node2D
var hex

func valid_cell(check_cell, grid):
	""" Checks the cell exists, is adjacent and is not occupied """
	# Hex exists in grid
	if HEX.axial_to_oddr(check_cell) in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
		# Hex is a neighbour of the current hex
		if hex:
			if check_cell in HEX.axial_neighbours(hex):
				# Hex occupied status
				return not grid.Grid[check_cell]['Piece']
		else:
			return not grid.Grid[check_cell]['Piece']
	else:
		false
		
func set_hex(new_cell, grid):
	""" Sets the position of the object on the grid.
	Assumes the tile coords are given in axial or cube.
	'old_loc' is used when the piece is already set and being moved. """
	
	var pos

	# Checks if Vector3 (cube)
	if typeof(new_cell) == 7:
		new_cell = Vector2i(new_cell.x, new_cell.y) # Converts to axial

	# Moves to new position if a valid cell
	if valid_cell(new_cell, grid):
		# Gets the centered position of the cell
		pos = grid.map_to_local(HEX.axial_to_oddr(new_cell))

		# Sets a reference to the parent node in the grid
		grid.Grid[new_cell]['Piece'] = piece
		
		# If the piece is currently stored somewhere, removes the reference
		if hex:
			grid.Grid[hex]['Piece'] = null
			
		hex = new_cell
		piece.position = pos


	# Returns the grid so we have one central location where all pieces are referenced
	return grid

func get_cell():
	return hex
