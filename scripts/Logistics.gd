extends Unit
 
class_name Logistics

func _ready():
	DAILY_DEPLETE = 0
	allied = true
	supplier = 1
	supplier_reserve = 10
 
func set_enemy():
	$Sprite2D.texture = load("res://assets/logir.png")
	allied = false
