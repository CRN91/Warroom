extends Unit
class_name Logistics

func _ready():
	update_ui()

func set_enemy():
	$Sprite2D.texture = load("res://assets/logir.png")
	team = 2
