extends Unit
 
class_name Logistics

func _ready():
	supplier = 1
	supplier_reserve = 10
	update_ui()
 
func set_enemy():
	$Sprite2D.texture = load("res://assets/logir.png")
	team = 2
