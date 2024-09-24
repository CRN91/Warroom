extends TileMap

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var Grid = {}
var highlights = []

func make_grid_axial():
	# Makes a hexagon of hexagons
	var shortest_width = 4 # width at shortest section of grid
	var grid_list = HEX.cube_spiral(Vector3i(0,0,0), 4)
	# Adding capital cities
	grid_list += [Vector2i(shortest_width/2,-shortest_width), 
	Vector2i(-shortest_width/2,shortest_width)]
	
	# Iterates through cells and adds them to dictionary and Godot grid
	for i in grid_list:
		var oddr = HEX.axial_to_oddr(i)
		
		Grid[Vector2i(i.x,i.y)] = { # Dictionary keys are axial
			"Piece": null
		}

		# Godot built in function uses oddr coordinates rather than axial
		set_cell(0, oddr, 0, Vector2i(0,0), 0)

# Removes the previous highlighted hexes the mouse went over
func erase_highlight(highlights):
	for i in highlights:
		erase_cell(1, i)
	return []

# Called when the node enters the scene tree for the first time.
func _ready():
	make_grid_axial()

func _process(delta):
	# Inbuilt functions use oddr coords
	var hex = HEX.oddr_to_axial(local_to_map(get_global_mouse_position()))
	
	# Deletes the previous highlights
	highlights = erase_highlight(highlights)
	# Sets a hex to be highlighted
	if Grid.has(hex):
		var oddr_hex = HEX.axial_to_oddr(hex)
		set_cell(1, oddr_hex, 1, Vector2i(0,0), 0)
		highlights.append(oddr_hex)
