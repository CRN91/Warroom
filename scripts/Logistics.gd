extends Unit
class_name Engineers

## Engineers: the builder/supplier unit. They ferry supplies, repair rail,
## build bridges and tunnels, and rail can only be laid near them.
## (Internal ids still use "logistics" — scene file, unit_type, card effects —
## so the card editor and old cards keep working.)

func _ready():
	update_ui()

func set_enemy():
	$Sprite2D.texture = load("res://assets/logir.png")
	team = 2
