extends Node2D
class_name HexGrid

## The hex board: tilemap rendering, the piece lookup table, A* pathfinding,
## and hover/selection highlights. Terrain (mountains/rivers) modifies the A*
## graph through disable_hex / disconnect_hexes.

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@onready var base_layer: TileMapLayer = $base
@onready var highlight_layer: TileMapLayer = $select

var Grid = {}                  # axial hex -> { "Piece": Node2D or null }
var terrain: TerrainManager    # set by Game after terrain generation

func _ready():
	make_grid_axial()

func make_grid_axial(shortest_width = 4):
	"""Creates a hexagonal board of the given radius."""
	var grid_list = HEX.cube_spiral(Vector3i(0, 0, 0), shortest_width)

	for i in grid_list:
		var oddr = HEX.axial_to_oddr(i)
		var hex = Vector2i(i.x, i.y)

		Grid[hex] = { "Piece": null }
		base_layer.set_cell(oddr, 0, Vector2i(0, 0), 0)
		_add_hex_to_astar(hex, oddr)

	_connect_all_astar_points()

# ── Pieces & positions ────────────────────────────────────────────────────────

func get_piece(hex): return Grid[hex]["Piece"]
func set_piece(hex, piece=null): Grid[hex]["Piece"] = piece
func get_hex_pos(hex): return base_layer.map_to_local(HEX.axial_to_oddr(hex))

# ── A* pathfinding ────────────────────────────────────────────────────────────

var astar = AStar2D.new()
var hex_to_id = {}
var id_to_hex = {}
var next_id = 0

func _add_hex_to_astar(hex, oddr):
	hex_to_id[hex] = next_id
	id_to_hex[next_id] = hex
	astar.add_point(next_id, base_layer.map_to_local(oddr))
	next_id += 1

func _connect_all_astar_points():
	for hex in Grid.keys():
		var id = hex_to_id[hex]
		for adj in HEX.axial_neighbours(hex):
			if adj in Grid.keys():
				astar.connect_points(id, hex_to_id[adj])

func enable_hex(hex):
	if hex_to_id.has(hex):
		astar.set_point_disabled(hex_to_id[hex], false)

func disable_hex(hex):
	if hex_to_id.has(hex):
		astar.set_point_disabled(hex_to_id[hex], true)

func sync_pathing(passable := []) -> void:
	"""Recomputes which A* points are blocked. Pass a `passable` list of hexes
	to treat as open even if occupied (used to path through friendly traffic).
	Call with no arguments afterwards to restore true collisions."""
	for hex in Grid.keys():
		var blocked = get_piece(hex) != null
		if terrain and terrain.is_mountain(hex):
			blocked = true
		if hex in passable:
			blocked = false
		astar.set_point_disabled(hex_to_id[hex], blocked)

func get_hex_path(start_hex: Vector2i, end_hex: Vector2i) -> PackedVector2Array:
	"""Path as world positions (for drawing lines)."""
	if not hex_to_id.has(start_hex) or not hex_to_id.has(end_hex):
		return PackedVector2Array()
	return astar.get_point_path(hex_to_id[start_hex], hex_to_id[end_hex])

func get_map_path(start_hex: Vector2i, end_hex: Vector2i) -> Array[Vector2i]:
	"""Path as hex coordinates (for actually moving)."""
	if not hex_to_id.has(start_hex) or not hex_to_id.has(end_hex):
		return []
	var hex_path: Array[Vector2i] = []
	for id in astar.get_id_path(hex_to_id[start_hex], hex_to_id[end_hex]):
		hex_path.append(id_to_hex[id])
	return hex_path

func disconnect_hexes(hex_a: Vector2i, hex_b: Vector2i):
	if hex_to_id.has(hex_a) and hex_to_id.has(hex_b):
		astar.disconnect_points(hex_to_id[hex_a], hex_to_id[hex_b])

func connect_hexes(hex_a: Vector2i, hex_b: Vector2i):
	if hex_to_id.has(hex_a) and hex_to_id.has(hex_b):
		astar.connect_points(hex_to_id[hex_a], hex_to_id[hex_b], true)

# ── Hover & selection highlights ──────────────────────────────────────────────

var highlights = []
var selected = null

func select_hex(oddr_hex):
	deselect()
	selected = oddr_hex

func deselect():
	if selected != null:
		highlight_layer.erase_cell(selected)
		selected = null

func _process(_delta):
	var hex = HEX.oddr_to_axial(base_layer.local_to_map(get_global_mouse_position()))

	for h in highlights:
		highlight_layer.erase_cell(h)
	highlights.clear()

	if Grid.has(hex):
		var oddr_hex = HEX.axial_to_oddr(hex)
		highlight_layer.set_cell(oddr_hex, 1, Vector2i(0, 0), 0)
		highlights.append(oddr_hex)

	if selected != null:
		highlight_layer.set_cell(selected, 2, Vector2i(0, 0), 0)
