extends Node2D
class_name Attack

@export var damage: int = 99
@export var attack_cost: int = 0    
@export var attack_range: int = 1   

var ally: Node2D

func _ready():
	ally = get_parent()

func attack(enemy, damage_override = null):
	var dmg = damage
	if damage_override:
		dmg = damage_override

	var destroyed := false

	if enemy.combatant():
		if ally.team != enemy.team:
			destroyed = enemy.deplete(dmg)
	else:
		destroyed = enemy.deplete(dmg)

	if attack_cost > 0:
		ally.deplete(attack_cost)

	return destroyed

func get_damage():
	return damage

func get_range():
	return attack_range
