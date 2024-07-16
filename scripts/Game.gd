extends Node2D

const PIECE = preload("res://scenes/piece.tscn") 
const CITY = preload("res://scenes/city.tscn")

@onready var grid = %Grid

func _ready():
	var city = CITY.instantiate()
	city.set_pos(Vector2i(0,-2), grid)
	add_child(city)
	
	var ene_cap = CITY.instantiate()
	ene_cap.set_pos(Vector2i(2,-4), grid)
	add_child(ene_cap)
	
	var own_cap = CITY.instantiate()
	own_cap.set_pos(Vector2i(-2,4), grid)
	add_child(own_cap)
	
func _process(delta):
	if Input.is_action_just_pressed("next"):
		var troop = PIECE.instantiate()
		add_child(troop)
		troop.move_to(Vector2i(0,3))
		
	
