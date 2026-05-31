extends Unit
class_name Artillery

@onready var attack_comp = $Attack

func _ready():
	allied       = true
	DAILY_DEPLETE = 3  

func combatant(): return true

func set_enemy():
	$Sprite2D.texture = load("res://assets/artilleryr.png")
	allied = false

func get_attack_range() -> int:
	return attack_comp.attack_range

func attack(enemy, damage = -1):
	if not frozen:
		frozen = true
		return attack_comp.attack(enemy, damage)
