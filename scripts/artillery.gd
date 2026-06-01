extends Unit
class_name Artillery

func _ready():
	allied = true

func combatant(): return true

func set_enemy():
	$Sprite2D.texture = load("res://assets/artilleryr.png")
	allied = false
