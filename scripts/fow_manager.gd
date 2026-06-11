extends Node
class_name FOWManager

## Fog of war: enemy pieces (and their rail) are visible only inside the
## player's vision bubbles — radius 2 around cities and units, extended to a
## unit's attack range if that's longer.

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const BASE_VISION := 2

var grid: Node
var rail_network: Node
var board: Board
var _flashed: Array = []            # pieces revealed by firing, until next turn
var _revealed_hexes: Dictionary = {} # hexes lifted by cards (photo flights), until next turn

func setup(_grid: Node, _rail_network: Node, _board: Board):
	grid = _grid
	rail_network = _rail_network
	board = _board

func flash(piece: Node2D) -> void:
	## A unit that fires gives away its position until the next turn.
	if piece not in _flashed:
		_flashed.append(piece)

func clear_flashes() -> void:
	_flashed.clear()
	_revealed_hexes.clear()

func reveal_hexes(hexes: Array) -> void:
	## Card-driven fog lift (photography flights): lasts until next turn.
	for h in hexes:
		_revealed_hexes[h] = true
	update_fow()

func update_fow():
	var visible_hexes = _get_visible_hexes()

	for hex in grid.Grid:
		var piece = grid.get_piece(hex)
		if piece:
			piece.visible = piece.team == 1 or visible_hexes.has(hex) \
				or _revealed_hexes.has(hex) \
				or (piece in _flashed and is_instance_valid(piece))

	for hex in rail_network.rail_hexes:
		if rail_network.rail_hexes[hex].has("node"):
			rail_network.rail_hexes[hex]["node"].visible = visible_hexes.has(hex)

func _get_visible_hexes() -> Dictionary:
	var visible = {}

	for city in board.cities:
		if is_instance_valid(city) and city.team == 1:
			for h in HEX.axial_radius(city.get_hex(), BASE_VISION):
				visible[h] = true
			visible[city.get_hex()] = true

	for unit in board.units:
		if is_instance_valid(unit) and unit.team == 1:
			var vision = max(BASE_VISION, unit.get_attack_range())
			for h in HEX.axial_radius(unit.get_hex(), vision):
				visible[h] = true
			visible[unit.get_hex()] = true

	return visible
