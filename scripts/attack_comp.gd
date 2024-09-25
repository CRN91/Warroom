extends Node2D

class_name Attack

@export var damage:= 99

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func attack(ally,enemy):
	if ally.is_allied() != enemy.is_allied():
		# Returns true if the enemy dies
		return enemy.deplete(damage)
			
func get_damage():
	return damage
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
