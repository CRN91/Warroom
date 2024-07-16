extends Node2D

const PIECE = preload("res://scenes/piece.tscn") 

func _process(delta):
	if Input.is_action_just_pressed("next"):
		var troop = PIECE.instantiate()
		add_child(troop)
		troop.move_to(Vector2i(0,3))
