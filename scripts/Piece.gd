extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@onready var grid = $"../Grid"

# Global coordinates of piece
var pos_a = Vector2i(0,0)
var supplies = 100

# Checks the coords given relate to a valid hex
func valid_coords(cell):
	# Checks cell exists and is not occupied
	if cell in grid.get_used_cells_by_id(0, 0, Vector2i(0, 0)):
		if not grid.Grid[cell]['Occupied']:
			return true
	else:
		false
	
# Takes a cube or axial coordinate
func move_to(new_cell):
	print(new_cell)
	if typeof(new_cell) == 7:
		new_cell = Vector2i(new_cell.x,new_cell.y) # Converts cube to axial
	var oddr_cell = HEX.axial_to_oddr(new_cell)
	print("help")
	if valid_coords(oddr_cell):
		print("check")
		position = grid.map_to_local(oddr_cell)
		# BUG: Race condition when accessing grid between multiple pieces
		grid.Grid[oddr_cell]['Occupied'] = true
		grid.Grid[HEX.axial_to_oddr(pos_a)]['Occupied'] = false 
		pos_a = new_cell
		
func adjacent_move(direction):
	move_to(HEX.cube_neighbor(HEX.axial_to_cube(pos_a), direction))
	
# Called when the node enters the scene tree for the first time.
func _ready():
	#move_to(Vector2i(1,3))
	pass
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_just_pressed("e"):
		adjacent_move(0)
	elif Input.is_action_just_pressed("ne"):
		adjacent_move(1)
	elif Input.is_action_just_pressed("nw"):
		adjacent_move(2)
	elif Input.is_action_just_pressed("w"):
		adjacent_move(3)
	elif Input.is_action_just_pressed("sw"):
		adjacent_move(4)
	elif Input.is_action_just_pressed("se"):
		adjacent_move(5)
