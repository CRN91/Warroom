extends Unit
class_name Infantry

@onready var attack_comp = $Attack

func _ready():
	allied = true

func combatant(): return true

func set_enemy():
	$Sprite2D.texture = load("res://assets/troopsr.png")
	allied = false

func get_damage() -> int:
	return attack_comp.damage

## Deals damage — no frozen check here.
## Freeze happens at set_target() time (player's action).
## This is called during end-of-day simultaneous resolution only.
func attack(enemy, damage = -1) -> bool:
	return attack_comp.attack(enemy, damage)
