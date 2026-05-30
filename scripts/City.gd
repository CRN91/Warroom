extends Unit
 
class_name City
 
@export var hex_tile: Vector2i
 
func _ready():
	resource_comp.set_max_resources(1000)
	resource_comp.set_resupply_rate(1000)
	supplier = 2
 
func set_hex(hex, grid):
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
func move_to(_hex, grid):
	return grid
