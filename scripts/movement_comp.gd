extends Node2D

class_name movement_comp

func valid_location(cell, grid):
	""" Checks the cell exists and is not occupied """
	
	if cell in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
		if not grid.Grid[cell]['Piece']:
			return true
	else:
		false
		
func set_tile_loc(tile_loc, grid, old_loc = false):
	""" Sets the position of the object on the grid.
	Assumes the tile coords are given in axial or cube.
	'old_loc' is used when the piece is already set and being moved. """
	
	var mutex = Mutex.new()
	
	# Checks if Vector3 (cube)
	if typeof(tile_loc) == 7:
		pos = Vector2i(tile_loc.x, tile_loc.y)
		
	# Moves to new position if a valid location
	if valid_location(tile_loc, grid):
		# Gets the centered position of the coord
		pos = grid.map_to_local(tile_loc)
		
		# Locks thread when altering the grid
		mutex.lock()
		grid.Grid[tile_loc]['Piece'] = self
		if old_loc:
			grid.Grid[old_loc]['Piece'] = false
		mutex.unlock()
		
		return pos
	else:
		return null	
	
		
		
		
		
		
	
	
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
