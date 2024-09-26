extends Node2D

class_name Attack

@export var damage:= 99
@export var ally: Node2D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func attack(enemy, specific_damage):
	if specific_damage == -1:
		specific_damage = damage
	if enemy.combatant():
		if ally.is_allied() != enemy.is_allied():
			# Returns true if the enemy dies
			return enemy.deplete(specific_damage)
	else:
		return enemy.deplete(specific_damage)
			
func get_damage():
	return damage
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
