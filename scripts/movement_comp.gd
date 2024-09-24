extends Node2D

class_name Movement

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@export var piece: Node2D
var START_CELL := Vector2i(0,0)
var cell: Vector2i

func valid_cell(check_cell, grid):
	""" Checks the cell exists and is not occupied """
	if check_cell in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
		return not grid.Grid[check_cell]['Piece']
	else:
		false
		
func set_cell(new_cell, grid, parent):
	""" Sets the position of the object on the grid.
	Assumes the tile coords are given in axial or cube.
	'old_loc' is used when the piece is already set and being moved. """
	
	var mutex = Mutex.new()
	var pos
	
	# Checks if Vector3 (cube)
	if typeof(new_cell) == 7:
		new_cell = Vector2i(new_cell.x, new_cell.y) # Converts to axial
		
	# Moves to new position if a valid cell
	if valid_cell(new_cell, grid):
		# Gets the centered position of the cell
		pos = grid.map_to_local(HEX.axial_to_oddr(new_cell))
		
		# Locks thread when altering the grid
		grid.Grid[new_cell]['Piece'] = parent
		if self.cell:
			grid.Grid[self.cell]['Piece'] = null
		
		piece.position = pos
	return grid
	
