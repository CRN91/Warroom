extends Node
class_name FOWManager

var game: Node2D

func setup(_game: Node2D):
	game = _game

# ── Fog of War ───────────────────────────────────────────────────────────

func update_fow():
	var visible_hexes = _get_visible_hexes()

	for hex in game.grid.Grid:
		var piece = game.get_piece(hex)
		if piece:
			piece.visible = piece.team == 1 or visible_hexes.has(hex)

	for hex in game.rail_hexes:
		if game.rail_hexes[hex].has("node"):
			game.rail_hexes[hex]["node"].visible = visible_hexes.has(hex)

func _get_visible_hexes() -> Dictionary:
	""" Calculates all hexes currently visible to the player """
	var visible = {}

	for city in game.cities:
		if city.team == 1:
			for h in game.HEX.axial_radius(city.get_hex(), 2):
				visible[h] = true

	for unit in game.units:
		if unit.team == 1:
			var vision = max(2, unit.get_attack_range())
			for h in game.HEX.axial_radius(unit.get_hex(), vision):
				visible[h] = true

	return visible
