extends TileMap

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

# ── Setup ───────────────────────────────────────────────────────────

var Grid = {}

func _ready():
	make_grid_axial()

func make_grid_axial(shortest_width = 4):
	"""Creates the a grid where the tiles are hexagons"""
	
	# Gets all the cube coordiantes for the grid
	var grid_list = HEX.cube_spiral(Vector3i(0,0,0), shortest_width)

	# Assigns the axial coordinate as the key for referencing the grid and sets its position on the screen
	for i in grid_list:
		var oddr = HEX.axial_to_oddr(i)
		var hex = Vector2i(i.x, i.y)

		Grid[hex] = {
			"Piece": null
			}
		set_cell(0, oddr, 0, Vector2i(0,0), 0)

		_add_hex_to_astar(hex,oddr)
	_connect_all_astar_points()
	
# ── Grid Updating ───────────────────────────────────────────────────────────

func get_piece(hex): return Grid[hex]["Piece"]
func set_piece(hex, piece=null): Grid[hex]["Piece"] = piece
func get_hex_pos(hex): return map_to_local(HEX.axial_to_oddr(hex))

func _update_grid(hex, disable=true):
	var id = hex_to_id[hex]
	astar.set_point_disabled(id, disable)
	
func enable_hex(hex):
	_update_grid(hex, false)

func disable_hex(hex):
	_update_grid(hex)

func get_hex_path(start_hex: Vector2i, end_hex: Vector2i) -> PackedVector2Array:
	if not hex_to_id.has(start_hex) or not hex_to_id.has(end_hex):
		return PackedVector2Array()

	var start_id = hex_to_id[start_hex]
	var end_id = hex_to_id[end_hex]

	return astar.get_point_path(start_id, end_id)

func get_map_path(start_hex: Vector2i, end_hex: Vector2i) -> Array[Vector2i]:
	if not hex_to_id.has(start_hex) or not hex_to_id.has(end_hex):
		return []

	var start_id = hex_to_id[start_hex]
	var end_id = hex_to_id[end_hex]
	
	var id_path = astar.get_id_path(start_id, end_id)
	
	var hex_path: Array[Vector2i] = []
	for id in id_path:
		hex_path.append(id_to_hex[id])
		
	return hex_path

# ── A* Algorithm Auto Pathing ────────────────────────────────────────────

var astar = AStar2D.new()
var hex_to_id = {}
var id_to_hex = {}
var next_id = 0

func _add_hex_to_astar(hex, oddr):
	"""Adds the hex to the A* grid"""
	hex_to_id[hex] = next_id
	id_to_hex[next_id] = hex
	astar.add_point(next_id, map_to_local(oddr))
	next_id += 1

func _connect_all_astar_points():
	"""Connects all the points in the A* graph"""
	for hex in Grid.keys():
		var id = hex_to_id[hex]
		for adj in HEX.axial_neighbours(hex):
			if adj in Grid.keys():
				astar.connect_points(id, hex_to_id[adj])

# ── Selection ─────────────────────────────────────────────────────────────────

var highlights = []
var selected

func erase_highlight(highlights):
	for i in highlights:
		erase_cell(1, i)
	return []

func select_hex(oddr_hex):
	deselect()
	selected = oddr_hex

func deselect():
	if selected:
		erase_cell(1,selected)
		selected = null

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

	if selected:
		set_cell(1, selected, 2, Vector2i(0,0), 0)
