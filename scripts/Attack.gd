extends Node2D

class_name Attack

@export var damage:= 99

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func attack(enemy):
	enemy.deplete(damage)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
