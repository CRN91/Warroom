extends Unit
class_name Artillery

func _ready():
	update_ui()

func is_combatant(): return true

func set_enemy():
	$Sprite2D.texture = load("res://assets/artilleryr.png")
	team = 2
