extends Unit
 
class_name City
 
@export var hex_tile: Vector2i

func _ready():
	supplier = 2
 
func set_hex(hex, grid):
	grid.disable_hex(hex)
	return movement_comp.set_hex(hex, grid)
 
func set_enemy():
	$Sprite2D.texture = load("res://assets/cityr.png")
	allied = false

# Cities never freeze - override base
func unfreeze():
	pass
 
func is_frozen():
	return false
 
# Cities don't move
func move_to(_hex, _old_hex, grid):
	return grid
