extends Node2D
class_name Attack

@export var damage: int = 99
@export var attack_cost: int = 0    # Resources the attacker spends per shot
@export var attack_range: int = 1   # Max hex distance this unit can fire

var ally: Node2D

func _ready():
	ally = get_parent()

## Fires at enemy. Returns true if enemy is destroyed.
## Caller is responsible for range checking before calling this.
func attack(enemy, damage_override = null):
	var dmg = damage
	if damage_override:
		dmg = damage_override

	var destroyed := false

	if enemy.combatant():
		if ally.is_allied() != enemy.is_allied():
			destroyed = enemy.deplete(dmg)
	else:
		destroyed = enemy.deplete(dmg)

	# Deplete attacker's own resources (ammo / exertion cost)
	if attack_cost > 0:
		ally.deplete(attack_cost)

	return destroyed

func get_damage():
	return damage

func get_range():
	return attack_range
