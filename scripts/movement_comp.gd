extends Node2D

class_name movement_comp

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@export var START_CELL := Vector2i(0,0)
@onready var grid = %Grid
var cell

func valid_cell(check_cell):
	""" Checks the csell exists and is not occupied """
	pass
	#if check_cell in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
	#if not grid.Grid[check_cell]['Piece']:
	#	return true
#	else:
	#	false
		
func set_cell(new_cell):
	""" Sets the position of the object on the grid.
	Assumes the tile coords are given in axial or cube.
	'old_loc' is used when the piece is already set and being moved. """
	
	var mutex = Mutex.new()
	var pos
	
	# Checks if Vector3 (cube)
	if typeof(new_cell) == 7:
		new_cell = Vector2i(new_cell.x, new_cell.y) # Converts to axial
		
	# Moves to new position if a valid cell
	if valid_cell(new_cell):
		# Gets the centered position of the cell
		pos = grid.map_to_local(new_cell)
		
		# Locks thread when altering the grid
		mutex.lock()
		grid.Grid[new_cell]['Piece'] = self
		if self.cell:
			grid.Grid[self.cell]['Piece'] = false
		mutex.unlock()
		
		return pos
	else:
		return null
	
func move_adjacent(direction):
	""" Sets the cell to the adjacent cell. """
	set_cell(HEX.cube_neighbor(HEX.axial_to_cube(self.cell), direction))
		
# Called when the node enters the scene tree for the first time.
func _ready():
	self.cell = START_CELL
	set_cell(self.cell)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
