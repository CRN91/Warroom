extends Unit
class_name City
 
@export var hex_tile: Vector2i
var is_hq: bool = false
var original_texture: Texture2D
 
func _ready():
	supplier = 2
	if has_node("Sprite2D"):
		original_texture = $Sprite2D.texture
	update_ui()
 
func set_hex(hex, grid):
	grid.disable_hex(hex)
	return movement_comp.set_hex(hex, grid)
 
func set_enemy():
	if has_node("Sprite2D"):
		$Sprite2D.texture = load("res://assets/cityr.png")
	modulate = Color(1, 1, 1)
	team = 2

func set_neutral():
	team = 0
	modulate = Color(0.6, 0.6, 0.6) # Tints it gray for neutral

func set_player():
	team = 1
	modulate = Color(1, 1, 1)
	if has_node("Sprite2D") and original_texture:
		$Sprite2D.texture = original_texture
 
func unfreeze():
	pass
 
func is_frozen():
	return false
 
func move_to(_hex, _old_hex, grid):
	return grid
	
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
