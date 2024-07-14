extends Node2D
@onready var grid = $"../Grid"

# Global coordinates of piece
var pos = Vector2i(0,0)
var supplies = 100

# Checks the coords given relate to a valid hex
func valid_coords(coords):
	if coords in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
		return true
	else:
		false
	
# Moves piece to grid coordinates
func move_to(new_cell):
	if valid_coords(new_cell):
		pos = new_cell
		var tiles = grid.get_used_cells_by_id(0, 0, Vector2i(0, 0))
		# Size of tiles
		var tile_size = grid.tile_set.tile_size
		# Top cell, position calculated relative to here (origin)
		var start_cell = Vector2i(3,0)
		var world_position = (start_cell * tile_size) + (tile_size / 2)
		# Coordinate difference between origin
		var cell_difference = new_cell - start_cell
		
		var y_offset = cell_difference.y * 0.75 * tile_size.y
		var x_offset
		if cell_difference.y % 2:
			x_offset = (tile_size.x * cell_difference.x) + (tile_size.x / 2)
		else:
			x_offset = tile_size.x * cell_difference.x

		# This line sets the position of the game object in the scene
		position = Vector2(world_position.x + x_offset, world_position.y + y_offset)

func adjacent_move(direction):
	if direction == 'w':
		move_to(Vector2i(pos.x-1,pos.y))
	elif direction == 'e':
		move_to(Vector2i(pos.x+1,pos.y))
	elif direction == 'ne':
		if pos.y % 2:
			move_to(Vector2i(pos.x+1, pos.y-1))
		else:
			move_to(Vector2i(pos.x, pos.y-1))
	elif direction == 'nw':
		if pos.y % 2:
			move_to(Vector2i(pos.x, pos.y-1))
		else:
			move_to(Vector2i(pos.x-1, pos.y-1))
	elif direction == 'se':
		if pos.y % 2:
			move_to(Vector2i(pos.x+1, pos.y+1))
		else:
			move_to(Vector2i(pos.x, pos.y+1))
	elif direction == 'sw':
		if pos.y % 2:
			move_to(Vector2i(pos.x, pos.y+1))
		else:
			move_to(Vector2i(pos.x-1, pos.y+1))
	
# Called when the node enters the scene tree for the first time.
func _ready():
	move_to(pos)
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_just_pressed("ne"):
		adjacent_move("ne")
	if Input.is_action_just_pressed("nw"):
		adjacent_move("nw")
	if Input.is_action_just_pressed("e"):
		adjacent_move("e")
	if Input.is_action_just_pressed("w"):
		adjacent_move("w")
	if Input.is_action_just_pressed("sw"):
		adjacent_move("sw")
	if Input.is_action_just_pressed("se"):
		adjacent_move("se")
