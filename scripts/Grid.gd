extends TileMap

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var Grid = {}
var highlights = []

func make_grid_axial():
	# 7 wide 
	var grid_list = HEX.cube_spiral(Vector3i(0,0,0), 4)
	var offset_i
	for i in grid_list:
		offset_i = HEX.axial_to_oddr(i)
		Grid[offset_i] = {
			"Cube" : i,
			"Occupied": false 
		}
		set_cell(0, offset_i, 0, Vector2i(0,0), 0)

func erase_highlight(highlights):
	for i in highlights:
		erase_cell(1, i)
	return []

# Called when the node enters the scene tree for the first time.
func _ready():
	make_grid_axial()

func _process(delta):
	var hex = local_to_map(get_global_mouse_position())
	highlights = erase_highlight(highlights)
	
	if Grid.has(hex):
		print(HEX.oddr_to_axial(hex))
		set_cell(1, hex, 1, Vector2i(0,0), 0)
		highlights.append(hex)
