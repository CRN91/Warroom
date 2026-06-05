extends Unit
class_name City

@export var hex_tile: Vector2i
var is_hq: bool = false
var original_texture: Texture2D

func _ready():
	if has_node("Sprite2D"):
		original_texture = $Sprite2D.texture
	update_ui()

func next_day() -> bool:
	var sieged := _is_sieged()
	if sieged:
		var starved = resource_comp.clock_cycle_depleting_only()
		update_ui()
		return starved

	# Normal income, but routed through the modifier system so cards can boost or
	# cut a city's output (permanently, temporarily, player-only, this city only…).
	var base_rate: int = resource_comp.replenish_rate
	var rate: int = base_rate
	if game and game.modifiers:
		rate = int(round(game.modifiers.get_value("city_income", float(base_rate), self)))

	if rate > 0:
		resource_comp.replenish(rate)
		update_ui()
		return false
	else:
		var starved = resource_comp.deplete(resource_comp.deplete_rate)
		update_ui()
		return starved

# ── Disabling Movement and Freezing ─────────────────────────────────────

func unfreeze(): pass
func is_frozen(): return false
func move_to(_hex): return # Cities can't move
func set_hex(hex):
	grid.disable_hex(hex)
	return movement_comp.set_hex(hex, grid)

# ── Team ───────────────────────────────────────────────────────────────

func set_enemy():
	if has_node("Sprite2D"):
		$Sprite2D.texture = load("res://assets/cityr.png")
	modulate = Color(1, 1, 1)
	team = 2

func set_neutral():
	team = 0
	modulate = Color(0.6, 0.6, 0.6)

func set_player():
	team = 1
	modulate = Color(1, 1, 1)
	if has_node("Sprite2D") and original_texture:
		$Sprite2D.texture = original_texture

# ── Capturing ─────────────────────────────────────────────────────────────

func capture(new_team: int, game: Node):
	if is_hq:
		game._game_over(team == 1)
		return

	team = new_team
	resource_comp.resources = 500

	if team == 1:
		set_player()
	elif team == 2:
		set_enemy()

	print("%s captured by team %d" % [name, team])

func _is_sieged() -> bool:
	if not grid:
		return false
	for adj in HEX.axial_neighbours(get_hex()):
		if not grid.Grid.has(adj):
			continue
		var p = grid.get_piece(adj)
		if p and p.team != team and p.is_combatant():
			return true
	return false
