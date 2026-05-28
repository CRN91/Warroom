extends Unit
class_name Infantry

@onready var attack_comp   = $Attack
@onready var resupply_comp = $Resupply

func _ready(): allied = true
func combatant(): return true
func set_enemy():
	$Sprite2D.texture = load("res://assets/troopsr.png")
	allied = false

func attack(enemy, damage = -1):
	if not frozen:
		frozen = true
		return attack_comp.attack(enemy, damage)

func resupply_from(ally):
	if not frozen:
		frozen = true
		resupply_comp.resupply_from(ally)
