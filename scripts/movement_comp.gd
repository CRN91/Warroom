extends Node2D

class_name movement_comp

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
		
func set_cell(new_cell, grid):
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
		pos = grid.map_to_local(new_cell)
		
		# Locks thread when altering the grid
		mutex.lock()
		grid.Grid[new_cell]['Piece'] = true
		if self.cell:
			grid.Grid[self.cell]['Piece'] = false
		mutex.unlock()
		
		piece.position = pos
	return grid
	
func move_adjacent(direction):
	""" Sets the cell to the adjacent cell. """
	pass
	#set_cell(HEX.cube_neighbor(HEX.axial_to_cube(self.cell), direction))
		
# Called when the node enters the scene tree for the first time.
func _ready():
	pass
	#self.cell = START_CELL
	#set_cell(self.cell)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
