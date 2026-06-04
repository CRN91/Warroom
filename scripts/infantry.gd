extends Unit
class_name Infantry

func _ready():
	update_ui()

func combatant(): return true

func set_enemy():
	$Sprite2D.texture = load("res://assets/troopsr.png")
	team = 2
