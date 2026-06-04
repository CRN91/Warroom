extends Node
class_name FOWManager

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var grid: Node
var rail_network: Node
var cities: Array
var units: Array

func setup(_grid: Node, _rail_network: Node, _cities: Array, _units: Array):
	grid = _grid
	rail_network = _rail_network
	cities = _cities
	units = _units

# ── Fog of War ───────────────────────────────────────────────────────────

func update_fow():
	var visible_hexes = _get_visible_hexes()

	for hex in grid.Grid:
		var piece = grid.get_piece(hex)
		if piece:
			piece.visible = piece.team == 1 or visible_hexes.has(hex)
			
	for hex in rail_network.rail_hexes:
		if rail_network.rail_hexes[hex].has("node"):
			rail_network.rail_hexes[hex]["node"].visible = visible_hexes.has(hex)

func _get_visible_hexes() -> Dictionary:
	""" Calculates all hexes currently visible to the player """
	var visible = {}

	for city in cities:
		if city.team == 1:
			for h in HEX.axial_radius(city.get_hex(), 2):
				visible[h] = true

	for unit in units:
		if unit.team == 1:
			var vision = 2
			if unit.has_method("get_attack_range"):
				vision = max(2, unit.get_attack_range())
				
			for h in HEX.axial_radius(unit.get_hex(), vision):
				visible[h] = true

	return visible
