extends TileMap

var Grid = {}
var highlights = []
@onready var piece = $"../Piece"

func axial_to_oddr(hex):
	var col = hex.x + (hex.y - (hex.y&1)) / 2
	var row = hex.y
	return Vector2i(col, row)

var cube_direction_vectors = [
	Vector3i(+1, 0, -1), Vector3i(+1, -1, 0), Vector3i(0, -1, +1), 
	Vector3i(-1, 0, +1), Vector3i(-1, +1, 0), Vector3i(0, +1, -1), 
]

func cube_distance(a, b):
	var vec = a - b
	return max(abs(vec.x), abs(vec.y), abs(vec.z)) 

func cube_neighbor(cube, direction):
	return cube + cube_direction_vectors[direction]

func cube_ring(center, radius):
	var results = []
	var hex = center + cube_direction_vectors[4] * radius

	for i in range(6):
		for j in range(radius):
			results.append(hex)
			hex = cube_neighbor(hex, i)
	return results

func cube_spiral(center, radius):
	var results = [center]
	for k in range(1,radius):
		results = results + cube_ring(center, k)
	return results

func make_grid_axial():
	# 7 wide 
	var grid_list = cube_spiral(Vector3i(0,0,0), 4)
	var offset_i
	for i in grid_list:
		offset_i = axial_to_oddr(i)
		Grid[offset_i] = {
			"Cube" : i
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
		print(hex)
		set_cell(1, hex, 1, Vector2i(0,0), 0)
		highlights.append(hex)
