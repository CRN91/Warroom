extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const INFANTRY = preload("res://scenes/infantry.tscn")

@onready var grid = %Grid

func _ready():
	var piece = INFANTRY.instantiate()
	add_child(piece)
	piece.move_to(Vector2i(2,1), grid)
	
func _process(delta):
	if Input.is_action_just_pressed("next"):
		var troop = INFANTRY.instantiate()
		add_child(troop)
		
