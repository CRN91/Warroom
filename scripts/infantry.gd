extends Unit
class_name Infantry

func _ready():
	$Sprite2D.material.set_shader_parameter("new_color", Color(0.126, 0.207, 0.065, 1.0))
	update_ui()

func is_combatant(): return true
